# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "websocket-client-simple"
require "redmine_ai_helper/chat_channel/base_adapter"

module RedmineAiHelper
  module ChatChannel
    module Adapters
      # Discord adapter using the Gateway API (v10): an outgoing WebSocket
      # connection to Discord, so no public URL is required. REST calls
      # (/users/@me, /gateway/bot, /channels/...) go through Net::HTTP with the
      # bot token. Only the GUILD_MESSAGES and DIRECT_MESSAGES intents are used;
      # the privileged MESSAGE_CONTENT intent is not required because Discord
      # still delivers the full content of messages that mention the bot and of
      # direct messages, which is exactly what this integration reacts to. The
      # bot token is never written to the log or to any exception message.
      class DiscordAdapter < BaseAdapter
        # Raised on authentication/configuration failures (REST 401, gateway
        # close codes 4004/4013/4014). Classified as a fatal config error so
        # the gateway exits cleanly and the supervisor does not retry into the
        # same broken credentials (ADR-006). Token values never appear here.
        class DiscordApiError < StandardError; end

        # Raised on non-authentication REST failures (other 4xx/5xx, exhausted
        # rate-limit retries). Not fatal: the supervisor may restart. Carries
        # the HTTP status and the Discord error code so callers can react to
        # specific conditions (e.g. "thread already exists").
        class DiscordRequestError < StandardError
          # @return [Integer, nil] the HTTP status code
          attr_reader :status
          # @return [Integer, nil] the Discord JSON error code, when present
          attr_reader :code

          # @param message [String] human-readable error (never the token)
          # @param status [Integer, nil] HTTP status code
          # @param code [Integer, nil] Discord error code
          def initialize(message, status: nil, code: nil)
            super(message)
            @status = status
            @code = code
          end
        end

        # Base URL of the Discord REST API (v10).
        DISCORD_API_BASE = "https://discord.com/api/v10"
        # Gateway API version and payload encoding. Both are required query
        # params on the gateway WebSocket URL; omitting them connects to
        # Discord's current default version, which can change unannounced.
        GATEWAY_QUERY_STRING = "v=10&encoding=json"
        # Open/read timeout for every REST call (contract: 10 seconds).
        HTTP_TIMEOUT_SECONDS = 10
        # Upper bound of the exponential reconnect backoff.
        MAX_BACKOFF_SECONDS = 60
        # Replies longer than this are split before posting (Discord's hard
        # limit is 2,000; 1,900 leaves headroom).
        MAX_MESSAGE_LENGTH = 1900
        # GUILD_MESSAGES (1<<9) + DIRECT_MESSAGES (1<<12). No privileged intent.
        GATEWAY_INTENTS = 4608
        # Maximum number of times a 429 response is retried before giving up.
        MAX_RATE_LIMIT_RETRIES = 3
        # Poll interval while waiting for the Hello opcode that carries the
        # real heartbeat interval.
        HELLO_WAIT_SECONDS = 1
        # Channel types that are threads (announcement, public, private).
        THREAD_CHANNEL_TYPES = [ 10, 11, 12 ].freeze
        # Message types this integration reacts to: DEFAULT and REPLY.
        REPLYABLE_MESSAGE_TYPES = [ 0, 19 ].freeze
        # Gateway close codes that indicate a fatal configuration problem.
        FATAL_CLOSE_CODES = [ 4004, 4013, 4014 ].freeze
        # Discord error code returned when a message already has a thread.
        THREAD_ALREADY_EXISTS_CODE = 160004
        # Maximum length of an auto-generated thread name (Discord limit: 100).
        THREAD_NAME_MAX_LENGTH = 100
        # Reaction shown while a question is being processed (FR-009).
        PROCESSING_EMOJI = "\u{23F3}" # ⏳
        # Upper bound on @reply_targets: the gateway is a resident process, and
        # reply-mode entries have no other eviction path, so the map is capped
        # and the oldest entry is dropped once it is exceeded (FIFO). Losing an
        # old entry only widens the message #send_message references (the root
        # id fallback still resolves the right conversation).
        MAX_REPLY_TARGETS = 500
        # Upper bound on reply-chain hops walked by #walk_to_root. Each hop is
        # a blocking REST call on the WebSocket receive thread, so an
        # unbounded chain would stall heartbeat processing long enough to be
        # mistaken for a zombie connection. Beyond the limit, the
        # farthest-resolved message is treated as the root.
        MAX_REPLY_CHAIN_HOPS = 20

        # Gateway opcode 0: a dispatch event (READY, MESSAGE_CREATE, ...).
        OP_DISPATCH = 0
        # Gateway opcode 1: heartbeat (sent by us, or requested by the server).
        OP_HEARTBEAT = 1
        # Gateway opcode 2: Identify, sent after Hello to authenticate.
        OP_IDENTIFY = 2
        # Gateway opcode 7: the server asks us to reconnect.
        OP_RECONNECT = 7
        # Gateway opcode 9: the session is invalid; reconnect and re-Identify.
        OP_INVALID_SESSION = 9
        # Gateway opcode 10: Hello, carrying the heartbeat interval.
        OP_HELLO = 10
        # Gateway opcode 11: acknowledgement of one of our heartbeats.
        OP_HEARTBEAT_ACK = 11

        class << self
          # @return [String] the adapter identifier
          def channel_type
            "discord"
          end

          # Discord connects and posts with a single bot token; app_token is
          # unused.
          # @return [Array<Symbol>]
          def required_setting_fields
            [ :bot_token ]
          end
        end

        # The bot's own Discord user id, fetched via /users/@me on start.
        # @return [String, nil]
        attr_reader :bot_user_id

        def initialize
          super
          @stopped = false
          @reconnect_requested = false
          @connected = false
          @backoff = 1
          @heartbeat_acked = true
          @reply_targets = {}
          @actual_channels = {}
        end

        # Connects to the Discord gateway and blocks while receiving events.
        # Reconnects on Reconnect/Invalid Session opcodes, on missed heartbeat
        # acks (zombie connection), on socket errors and on clean closes that
        # never reached READY (all with exponential backoff). Authentication
        # failures (REST 401, close 4004/4013/4014) terminate without retry.
        # @return [void]
        def start
          @stopped = false
          @bot_user_id = fetch_bot_user_id
          ai_helper_logger.info "discord: starting gateway connection (bot user #{@bot_user_id})"
          until stopped?
            url = gateway_url
            begin
              listen(url)
              if @reconnect_requested
                reset_backoff
              elsif !@connected
                ai_helper_logger.warn "discord: connection ended before READY; backing off before reconnect"
                sleep(next_backoff) unless stopped?
              end
            rescue DiscordApiError
              raise
            rescue => e
              ai_helper_logger.error "discord: socket error: #{e.full_message}"
              sleep(next_backoff) unless stopped?
            end
          end
          ai_helper_logger.info "discord: adapter stopped"
        end

        # Closes the connection and lets #start return.
        # @return [void]
        def stop
          @stopped = true
          @connection_ended&.push(true)
          close_socket
        end

        # Whether READY has been received on the current socket.
        # @return [Boolean]
        def connected?
          @connected
        end

        # Handles one raw gateway payload (JSON text frame).
        # @param raw [String] the raw JSON payload
        # @return [void]
        def handle_gateway_message(raw)
          payload = JSON.parse(raw)
          @last_sequence = payload["s"] if payload["s"]
          case payload["op"]
          when OP_HELLO
            @heartbeat_interval = payload.dig("d", "heartbeat_interval").to_f / 1000.0
            send_identify
          when OP_HEARTBEAT
            send_heartbeat
          when OP_HEARTBEAT_ACK
            @heartbeat_acked = true
          when OP_RECONNECT, OP_INVALID_SESSION
            ai_helper_logger.info "discord: reconnect requested by gateway (op #{payload["op"]})"
            request_reconnect
          when OP_DISPATCH
            handle_dispatch(payload["t"], payload["d"] || {})
          else
            ai_helper_logger.debug "discord: ignoring opcode #{payload["op"].inspect}"
          end
        rescue JSON::ParserError => e
          ai_helper_logger.error "discord: failed to parse gateway payload: #{e.message}"
        end

        # Reacts to a gateway close frame, capturing fatal authentication
        # close codes so #start can terminate without retry.
        # @param code [Integer, nil] the WebSocket close code
        # @return [void]
        def handle_close_frame(code)
          if FATAL_CLOSE_CODES.include?(code)
            @fatal_close = DiscordApiError.new("Discord gateway closed with fatal code #{code}")
            ai_helper_logger.error "discord: gateway closed with fatal code #{code}"
          else
            ai_helper_logger.info "discord: gateway close frame received (code #{code})"
          end
          @connection_ended&.push(true)
        end

        # Posts a reply to the destination encoded in the thread_key, splitting
        # texts longer than the Discord message limit. In reply mode the first
        # chunk references the question message (message_reference).
        # @param channel_id [String] the channel the conversation is bound to
        #   (the post destination in reply mode)
        # @param thread_key [String] "{cid}:{tid}" or "{cid}:msg:{root}"
        # @param text [String] the reply body (Markdown as-is)
        # @return [void]
        def send_message(channel_id:, thread_key:, text:)
          target, reply_to = resolve_destination(channel_id, thread_key)
          split_text(text).each_with_index do |chunk, index|
            body = { content: chunk }
            body[:message_reference] = { message_id: reply_to } if reply_to && index.zero?
            post_message(target, body)
          end
        end

        # Adds the processing reaction (⏳) to the received message in the
        # channel it actually arrived in (FR-009).
        # @param message [IncomingMessage] the message being processed
        # @return [void]
        def notify_processing(message:)
          channel = actual_channel_for(message)
          add_reaction(channel, message.message_ts)
        end

        # Classifies DiscordApiError as a fatal configuration/credential error
        # so the gateway exits cleanly (exit 0) rather than retrying broken
        # credentials (ADR-006).
        # @param error [Exception] the error raised by the adapter
        # @return [Boolean]
        def fatal_config_error?(error)
          error.is_a?(DiscordApiError)
        end

        private

        # Whether #stop has been called.
        # @return [Boolean]
        def stopped?
          @stopped
        end

        # Fetches the bot's own user id and validates the bot token.
        # @return [String]
        def fetch_bot_user_id
          request(:get, "/users/@me")["id"]
        end

        # Fetches a fresh gateway WebSocket URL.
        # @return [String] the wss:// URL
        def gateway_url
          request(:get, "/gateway/bot")["url"]
        end

        # Connects the WebSocket and blocks until the connection ends, a
        # reconnect is requested, or the adapter is stopped. Re-raises a fatal
        # close error captured on the receive thread.
        # @param url [String] the wss:// gateway URL
        # @return [void]
        def listen(url)
          @connection_ended = Queue.new
          @reconnect_requested = false
          @connected = false
          @heartbeat_interval = nil
          @heartbeat_acked = true
          @last_sequence = nil
          @fatal_close = nil
          adapter = self
          @ws = WebSocket::Client::Simple.connect("#{url}?#{GATEWAY_QUERY_STRING}") do |ws|
            ws.on(:message) do |msg|
              case msg.type
              when :text  then adapter.send(:handle_gateway_message, msg.data)
              when :close then adapter.send(:handle_close_frame, msg.code)
              end
            end
            ws.on(:close) { |_error| adapter.send(:connection_ended!) }
            ws.on(:error) { |error| adapter.send(:socket_errored, error) }
          end
          heartbeat_loop
          raise @fatal_close if @fatal_close
        ensure
          close_socket
        end

        # Sends heartbeats on the interval announced in Hello. A heartbeat
        # whose ack never arrived before the next tick is a zombie connection
        # and forces a reconnect.
        # @return [void]
        def heartbeat_loop
          until stopped? || @reconnect_requested
            wait = @heartbeat_interval || HELLO_WAIT_SECONDS
            break if self.class.timed_queue_pop(@connection_ended, wait)
            next if @heartbeat_interval.nil?

            unless @heartbeat_acked
              ai_helper_logger.warn "discord: heartbeat not acknowledged; reconnecting (zombie connection)"
              request_reconnect
              break
            end
            @heartbeat_acked = false
            send_heartbeat
          end
        end

        # Sends the Identify payload with the minimal intents (no privileged
        # MESSAGE_CONTENT).
        # @return [void]
        def send_identify
          send_json(
            op: OP_IDENTIFY,
            d: {
              token: settings.bot_token,
              intents: GATEWAY_INTENTS,
              properties: { os: "linux", browser: "redmine_ai_helper", device: "redmine_ai_helper" }
            }
          )
        end

        # Sends a heartbeat carrying the last received sequence number.
        # @return [void]
        def send_heartbeat
          send_json(op: OP_HEARTBEAT, d: @last_sequence)
        end

        # Serializes and sends a gateway payload over the socket.
        # @param payload [Hash] the gateway payload
        # @return [void]
        def send_json(payload)
          @ws&.send(payload.to_json)
        end

        # Dispatches a gateway dispatch event (opcode 0).
        # @param type [String] the dispatch event name
        # @param data [Hash] the event payload
        # @return [void]
        def handle_dispatch(type, data)
          case type
          when "READY"
            @connected = true
            reset_backoff
            ai_helper_logger.info "discord: connection established (READY received)"
          when "MESSAGE_CREATE"
            process_message(data)
          end
        end

        # Converts a MESSAGE_CREATE event into an IncomingMessage and
        # dispatches it. Bot messages, the bot's own messages, system messages
        # and (in guilds) messages that do not mention the bot are ignored.
        # @param data [Hash] the MESSAGE_CREATE payload
        # @return [void]
        def process_message(data)
          return if data.dig("author", "bot")

          author_id = data.dig("author", "id")
          return if author_id.blank? || author_id == @bot_user_id
          return unless REPLYABLE_MESSAGE_TYPES.include?(data["type"])

          if data["guild_id"].blank?
            process_dm(data)
          else
            process_guild_message(data)
          end
        end

        # Handles a direct message: every message is a question. Continuation
        # is resolved by following the reply chain back to its root when the
        # message replies to one of the bot's answers.
        # @param data [Hash] the MESSAGE_CREATE payload
        # @return [void]
        def process_dm(data)
          channel_id = data["channel_id"]
          message_id = data["id"]
          thread_key = resolve_dm_thread_key(data, channel_id, message_id)
          record_reply_target(thread_key, message_id)
          record_actual_channel(message_id, channel_id)
          dispatch(IncomingMessage.new(
            channel_type: channel_type, channel_id: channel_id, thread_key: thread_key,
            message_ts: message_id, text: data["content"].to_s.strip, dm: true
          ))
        end

        # Handles a guild message that mentions the bot. In an existing thread
        # the conversation continues there (bindings resolve on the parent
        # channel); in a normal channel a thread is created, falling back to
        # reply mode when that is not possible.
        # @param data [Hash] the MESSAGE_CREATE payload
        # @return [void]
        def process_guild_message(data)
          content = data["content"].to_s
          return unless mentions_bot?(content)

          channel_id = data["channel_id"]
          message_id = data["id"]
          text = strip_mention(content)
          channel = safe_fetch_channel(channel_id)
          return unless channel

          if THREAD_CHANNEL_TYPES.include?(channel["type"])
            parent_id = channel["parent_id"]
            record_actual_channel(message_id, channel_id)
            dispatch(IncomingMessage.new(
              channel_type: channel_type, channel_id: parent_id,
              thread_key: "#{parent_id}:#{channel_id}", message_ts: message_id, text: text, dm: false
            ))
          else
            dispatch_with_thread(channel_id, message_id, text)
          end
        end

        # Creates a thread from the question message and dispatches into it;
        # falls back to reply mode when the thread cannot be created.
        # @param channel_id [String] the parent channel id
        # @param message_id [String] the question message id
        # @param text [String] the mention-stripped question text
        # @return [void]
        def dispatch_with_thread(channel_id, message_id, text)
          thread_id = create_thread(channel_id, message_id, text)
          record_actual_channel(message_id, channel_id)
          if thread_id
            dispatch(IncomingMessage.new(
              channel_type: channel_type, channel_id: channel_id,
              thread_key: "#{channel_id}:#{thread_id}", message_ts: message_id, text: text, dm: false
            ))
          else
            thread_key = "#{channel_id}:msg:#{message_id}"
            record_reply_target(thread_key, message_id)
            dispatch(IncomingMessage.new(
              channel_type: channel_type, channel_id: channel_id,
              thread_key: thread_key, message_ts: message_id, text: text, dm: false
            ))
          end
        end

        # Resolves the DM thread_key, following the reply chain to its root
        # when the message replies to one of the bot's answers. A reply to a
        # non-bot message, or a referenced message that cannot be fetched,
        # starts a new conversation.
        # @param data [Hash] the MESSAGE_CREATE payload
        # @param channel_id [String] the DM channel id
        # @param message_id [String] this message's id
        # @return [String] the thread_key
        def resolve_dm_thread_key(data, channel_id, message_id)
          referenced_id = data.dig("message_reference", "message_id")
          return "#{channel_id}:msg:#{message_id}" if referenced_id.blank?

          referenced = safe_fetch_message(channel_id, referenced_id)
          return "#{channel_id}:msg:#{message_id}" unless referenced && bot_authored?(referenced)

          "#{channel_id}:msg:#{walk_to_root(channel_id, referenced)}"
        end

        # Walks a reply chain back to its origin (the message with no
        # message_reference) and returns that message's id.
        # @param channel_id [String] the channel the chain lives in
        # @param message [Hash] the message to start walking from
        # @return [String] the origin message id
        def walk_to_root(channel_id, message)
          current = message
          hops = 0
          loop do
            referenced_id = current.dig("message_reference", "message_id")
            return current["id"] if referenced_id.blank?
            return current["id"] if hops >= MAX_REPLY_CHAIN_HOPS

            parent = safe_fetch_message(channel_id, referenced_id)
            return current["id"] if parent.nil?

            current = parent
            hops += 1
          end
        end

        # Fetches a channel, logging and swallowing non-fatal failures (a
        # permission problem or transient network error while resolving a
        # channel's type must drop only this message, not tear down the
        # gateway connection: raising here would escape into the WebSocket
        # gem's per-message rescue and force an immediate, unthrottled
        # reconnect). Fatal auth errors still propagate so #start can
        # terminate without retry.
        # @param channel_id [String] the channel id
        # @return [Hash, nil] the channel, or nil when it cannot be fetched
        def safe_fetch_channel(channel_id)
          fetch_channel(channel_id)
        rescue DiscordApiError
          raise
        rescue => e
          ai_helper_logger.warn "discord: failed to fetch channel #{channel_id}: #{e.message}"
          nil
        end

        # Whether the message was authored by the bot itself.
        # @param message [Hash] a message object
        # @return [Boolean]
        def bot_authored?(message)
          message.dig("author", "id") == @bot_user_id
        end

        # Fetches a message, logging and swallowing failures (a deleted or
        # inaccessible referenced message must not abort processing).
        # @param channel_id [String] the channel id
        # @param message_id [String] the message id
        # @return [Hash, nil] the message, or nil when it cannot be fetched
        def safe_fetch_message(channel_id, message_id)
          fetch_message(channel_id, message_id)
        rescue DiscordApiError
          raise
        rescue => e
          ai_helper_logger.warn "discord: failed to fetch referenced message: #{e.message}"
          nil
        end

        # Whether the content contains an explicit mention of the bot.
        # @param content [String] the message content
        # @return [Boolean]
        def mentions_bot?(content)
          content.include?("<@#{@bot_user_id}>") || content.include?("<@!#{@bot_user_id}>")
        end

        # Removes the bot mention markup from the question text.
        # @param content [String] the message content
        # @return [String]
        def strip_mention(content)
          content.gsub(/<@!?#{Regexp.escape(@bot_user_id.to_s)}>/, "").strip
        end

        # Records the question message id to reference when replying in reply
        # mode. Keyed by thread_key so a continuing conversation references its
        # latest question.
        # @param thread_key [String] the conversation thread_key
        # @param message_id [String] the question message id
        # @return [void]
        def record_reply_target(thread_key, message_id)
          @reply_targets.delete(thread_key)
          @reply_targets[thread_key] = message_id
          @reply_targets.delete(@reply_targets.each_key.first) while @reply_targets.size > MAX_REPLY_TARGETS
        end

        # Records the channel a received message actually arrived in, so the
        # processing reaction lands on the right message.
        # @param message_id [String] the message id
        # @param channel_id [String] the real channel the message is in
        # @return [void]
        def record_actual_channel(message_id, channel_id)
          @actual_channels[message_id] = channel_id
        end

        # The channel to react in for a message: the recorded real channel,
        # falling back to the thread_key (thread id in thread mode, channel id
        # in reply mode). Consumes the recorded entry.
        # @param message [IncomingMessage] the message being processed
        # @return [String] the channel id to react in
        def actual_channel_for(message)
          recorded = @actual_channels.delete(message.message_ts)
          return recorded if recorded

          if message.thread_key.include?(":msg:")
            message.thread_key.split(":msg:", 2).first
          else
            message.thread_key.split(":", 2).last
          end
        end

        # Parses a thread_key into the REST destination and the message to
        # reply to. Thread mode posts into the thread with no reference; reply
        # mode posts into the bound channel referencing the latest question.
        # @param channel_id [String] the bound channel (reply-mode destination)
        # @param thread_key [String] the conversation thread_key
        # @return [Array(String, String)] destination channel id and reply-to
        #   message id (nil in thread mode)
        def resolve_destination(channel_id, thread_key)
          if thread_key.include?(":msg:")
            root = thread_key.split(":msg:", 2).last
            [ channel_id, @reply_targets[thread_key] || root ]
          else
            [ thread_key.split(":", 2).last, nil ]
          end
        end

        # Asks the receive loop to end so #start reconnects with a fresh URL.
        # @return [void]
        def request_reconnect
          @reconnect_requested = true
          @connection_ended&.push(true)
        end

        # The socket was closed by the remote side.
        # @return [void]
        def connection_ended!
          @connection_ended&.push(true)
        end

        # A socket error occurred; end the connection so #start can retry.
        # @param error [Exception] the socket error
        # @return [void]
        def socket_errored(error)
          ai_helper_logger.error "discord: websocket error: #{error.message}"
          @connection_ended&.push(true)
        end

        # Closes the socket, ignoring the usual close-time IO errors.
        # @return [void]
        def close_socket
          socket = @ws
          @ws = nil
          socket&.close
        rescue IOError, SystemCallError => e
          ai_helper_logger.debug "discord: error while closing socket: #{e.message}"
        end

        # Returns the current backoff delay and doubles it (capped).
        # @return [Integer] seconds to wait
        def next_backoff
          current = @backoff
          @backoff = [ @backoff * 2, MAX_BACKOFF_SECONDS ].min
          current
        end

        # Resets the backoff after a successful connection.
        # @return [void]
        def reset_backoff
          @backoff = 1
        end

        # Creates a thread from the question message. Returns the thread id
        # (equal to the message id) on success or when the message already has
        # a thread; returns nil (reply-mode fallback) when the thread cannot be
        # created for channel-type or permission reasons.
        # @param channel_id [String] the parent channel id
        # @param message_id [String] the question message id
        # @param text [String] the question text (used for the thread name)
        # @return [String, nil] the thread id, or nil to fall back to replies
        def create_thread(channel_id, message_id, text)
          request(:post, "/channels/#{channel_id}/messages/#{message_id}/threads",
                  body: { name: thread_name(text) })
          message_id
        rescue DiscordApiError
          raise
        rescue DiscordRequestError => e
          return message_id if e.code == THREAD_ALREADY_EXISTS_CODE

          ai_helper_logger.warn "discord: could not create thread (HTTP #{e.status}); falling back to reply mode"
          nil
        rescue => e
          ai_helper_logger.warn "discord: could not create thread (#{e.message}); falling back to reply mode"
          nil
        end

        # Truncates the question text into a valid thread name.
        # @param text [String] the question text
        # @return [String]
        def thread_name(text)
          name = text.to_s.strip.truncate(THREAD_NAME_MAX_LENGTH)
          name.empty? ? "AI Helper" : name
        end

        # Fetches a channel object.
        # @param channel_id [String] the channel id
        # @return [Hash] the channel object
        def fetch_channel(channel_id)
          request(:get, "/channels/#{channel_id}")
        end

        # Fetches a single message object.
        # @param channel_id [String] the channel id
        # @param message_id [String] the message id
        # @return [Hash] the message object
        def fetch_message(channel_id, message_id)
          request(:get, "/channels/#{channel_id}/messages/#{message_id}")
        end

        # Posts a message to a channel.
        # @param channel_id [String] the destination channel id
        # @param body [Hash] the message JSON body
        # @return [Hash] the created message object
        def post_message(channel_id, body)
          request(:post, "/channels/#{channel_id}/messages", body: body)
        end

        # Adds the processing reaction to a message.
        # @param channel_id [String] the channel the message is in
        # @param message_id [String] the message id
        # @return [void]
        def add_reaction(channel_id, message_id)
          emoji = URI.encode_www_form_component(PROCESSING_EMOJI)
          request(:put, "/channels/#{channel_id}/messages/#{message_id}/reactions/#{emoji}/@me")
        end

        # Splits a reply into chunks within the Discord message limit,
        # preferring paragraph boundaries, then line boundaries, then a hard
        # cut. No content is ever dropped.
        # @param text [String] the full reply
        # @return [Array<String>] the chunks to post in order
        def split_text(text)
          return [ text ] if text.length <= MAX_MESSAGE_LENGTH

          chunks = []
          remaining = text
          while remaining.length > MAX_MESSAGE_LENGTH
            slice = remaining[0, MAX_MESSAGE_LENGTH]
            cut = slice.rindex("\n\n") || slice.rindex("\n") || MAX_MESSAGE_LENGTH
            cut = MAX_MESSAGE_LENGTH if cut.zero?
            chunks << remaining[0, cut]
            remaining = remaining[cut..].to_s.sub(/\A\n+/, "")
          end
          chunks << remaining unless remaining.empty?
          chunks
        end

        # Builds an HTTPS client with the contract timeouts.
        # @param uri [URI] the request URI
        # @return [Net::HTTP]
        def build_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = HTTP_TIMEOUT_SECONDS
          http.read_timeout = HTTP_TIMEOUT_SECONDS
          http
        end

        # Performs a Discord REST call with the bot token. 401 raises
        # DiscordApiError (fatal, no retry); 429 waits retry_after and retries
        # up to the cap; other non-2xx responses raise DiscordRequestError. The
        # token is never included in any message. Returns the parsed JSON body
        # ({} when the body is empty, e.g. 204).
        # @param http_method [Symbol] :get, :post or :put
        # @param path [String] the API path (leading slash)
        # @param body [Hash, nil] the JSON body for writes
        # @return [Hash] the parsed response body
        def request(http_method, path, body: nil)
          uri = URI("#{DISCORD_API_BASE}#{path}")
          attempts = 0
          loop do
            attempts += 1
            response = build_http(uri).request(build_request(http_method, uri, body))
            code = response.code.to_i
            case code
            when 200..299
              return response.body.to_s.empty? ? {} : JSON.parse(response.body)
            when 401
              raise DiscordApiError, "Discord API #{http_method.upcase} #{path} failed: unauthorized"
            when 429
              raise DiscordRequestError.new("Discord API rate limit exceeded for #{path}", status: 429) if attempts > MAX_RATE_LIMIT_RETRIES

              sleep(retry_after_seconds(response))
            else
              raise DiscordRequestError.new(
                "Discord API #{http_method.upcase} #{path} failed: HTTP #{code}",
                status: code, code: error_code(response)
              )
            end
          end
        end

        # Builds a Net::HTTP request with the auth header and JSON body.
        # @param http_method [Symbol] :get, :post or :put
        # @param uri [URI] the request URI
        # @param body [Hash, nil] the JSON body for writes
        # @return [Net::HTTPRequest]
        def build_request(http_method, uri, body)
          klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(http_method)
          req = klass.new(uri.request_uri)
          req["Authorization"] = "Bot #{settings.bot_token}"
          if body
            req["Content-Type"] = "application/json"
            req.body = body.to_json
          end
          req
        end

        # The retry_after value (seconds) from a 429 response body.
        # @param response [Net::HTTPResponse] the 429 response
        # @return [Float] seconds to wait
        def retry_after_seconds(response)
          body = JSON.parse(response.body.to_s)
          body["retry_after"].to_f
        rescue JSON::ParserError => e
          ai_helper_logger.debug "discord: could not parse retry_after from 429 body (#{e.message}); falling back to 1s"
          1.0
        end

        # The Discord error code from a non-2xx response body, if present.
        # @param response [Net::HTTPResponse] the error response
        # @return [Integer, nil]
        def error_code(response)
          JSON.parse(response.body.to_s)["code"]
        rescue JSON::ParserError, TypeError
          nil
        end
      end
    end
  end
end
