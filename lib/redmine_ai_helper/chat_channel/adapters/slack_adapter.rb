# frozen_string_literal: true

require "json"
require "net/http"
require "websocket-client-simple"
require "redmine_ai_helper/chat_channel/base_adapter"
require "redmine_ai_helper/chat_channel/history_message"

module RedmineAiHelper
  module ChatChannel
    # Concrete chat tool adapter implementations. One file per tool.
    module Adapters
      # Slack adapter using Socket Mode: an outgoing WebSocket connection
      # obtained via apps.connections.open, so no public URL is required.
      # Web API calls (auth.test, chat.postMessage) go through Net::HTTP
      # directly. Tokens are never written to the log.
      class SlackAdapter < BaseAdapter
        # Raised when a Slack Web API call returns ok:false. Authentication
        # errors are not retried: the gateway terminates with this error.
        class SlackApiError < StandardError; end

        # Base URL of the Slack Web API.
        SLACK_API_BASE = "https://slack.com/api"
        # Open/read timeout for every Web API call (contract: 10 seconds).
        HTTP_TIMEOUT_SECONDS = 10
        # Interval between health-check pings on the WebSocket.
        PING_INTERVAL_SECONDS = 30
        # Upper bound of the exponential reconnect backoff.
        MAX_BACKOFF_SECONDS = 60
        # Reconnect when this many consecutive pings got no pong.
        MAX_MISSED_PONGS = 2
        # Replies longer than this are split before posting (research.md R-008).
        MAX_MESSAGE_LENGTH = 3900
        # Messages requested per history page (Slack's maximum for a full page).
        HISTORY_PAGE_LIMIT = 200
        # Subtypes that carry an ordinary contribution to the discussion.
        # Everything else (joins, leaves, edits, pins, ...) is a system message
        # and is not imported. bot_message stays on the list because other
        # bots' messages are part of the discussion (FR-009).
        HISTORY_SUBTYPES = [ nil, "bot_message", "thread_broadcast", "file_share" ].freeze
        # Upper bound on the user id to display name cache. The gateway is a
        # resident process, so the map is capped and the oldest entry is
        # dropped once it is exceeded (FIFO), same as @reply_targets in the
        # Discord adapter. Losing an entry only costs one extra users.info call.
        MAX_DISPLAY_NAMES = 500

        class << self
          # @return [String] the adapter identifier
          def channel_type
            "slack"
          end

          # Socket Mode needs the app-level token, the Web API the bot token.
          # @return [Array<Symbol>]
          def required_setting_fields
            [ :app_token, :bot_token ]
          end
        end

        # The bot's own Slack user id, fetched via auth.test on start.
        # @return [String, nil]
        attr_reader :bot_user_id

        def initialize
          super
          @stopped = false
          @reconnect_requested = false
          @connected = false
          @backoff = 1
          @missed_pongs = 0
          @display_names = {}
        end

        # Connects to Slack and blocks while receiving events. Reconnects on
        # disconnect envelopes (immediately, with a fresh URL), on socket
        # errors (with exponential backoff), on missed pongs and on clean
        # closes that never received hello (suspected handshake rejection,
        # also backed off so a remote-side tight close loop cannot hammer
        # apps.connections.open). Auth errors (ok:false from the Web API)
        # terminate without retry.
        # @return [void]
        def start
          @stopped = false
          @bot_user_id = fetch_bot_user_id
          ai_helper_logger.info "slack: starting Socket Mode connection (bot user #{@bot_user_id})"
          until stopped?
            url = open_connection_url
            begin
              listen(url)
              if @reconnect_requested
                reset_backoff
              elsif !@connected
                ai_helper_logger.warn "slack: connection ended without hello; backing off before reconnect"
                sleep(next_backoff) unless stopped?
              end
            rescue SlackApiError
              raise
            rescue => e
              ai_helper_logger.error "slack: socket error: #{e.full_message}"
              sleep(next_backoff) unless stopped?
            end
          end
          ai_helper_logger.info "slack: adapter stopped"
        end

        # Closes the connection and lets #start return.
        # @return [void]
        def stop
          @stopped = true
          @connection_ended&.push(true)
          close_socket
        end

        # Whether the hello envelope has been received on the current socket.
        # @return [Boolean]
        def connected?
          @connected
        end

        # Dispatches one raw Socket Mode envelope (JSON text frame).
        # @param raw [String] the raw JSON payload
        # @return [void]
        def handle_envelope(raw)
          data = JSON.parse(raw)
          case data["type"]
          when "hello"
            @connected = true
            reset_backoff
            ai_helper_logger.info "slack: connection established (hello received)"
          when "disconnect"
            ai_helper_logger.info "slack: disconnect requested by Slack (reason: #{data["reason"]})"
            request_reconnect
          when "events_api"
            acknowledge(data["envelope_id"])
            process_event(data.dig("payload", "event") || {})
          else
            ai_helper_logger.debug "slack: ignoring envelope type #{data["type"].inspect}"
          end
        rescue JSON::ParserError => e
          ai_helper_logger.error "slack: failed to parse envelope: #{e.message}"
        end

        # Posts a reply into the given thread, splitting texts longer than
        # the Slack message limit at paragraph boundaries.
        # @param channel_id [String] the Slack channel id
        # @param thread_key [String] "{channel_id}:{thread_ts}"
        # @param text [String] the reply body (Markdown as-is)
        # @return [void]
        def send_message(channel_id:, thread_key:, text:)
          thread_ts = thread_key.split(":", 2).last
          split_text(text).each do |chunk|
            api_call("chat.postMessage", token: settings.bot_token,
                     params: { channel: channel_id, thread_ts: thread_ts, text: chunk })
          end
        end

        # Slack exposes both the thread replies and the channel history.
        # @return [Boolean]
        def supports_history?
          true
        end

        # Reads the replies of a thread through conversations.replies, paging
        # until Slack stops handing out a cursor.
        # @param channel_id [String] the Slack channel id
        # @param thread_key [String] "{channel_id}:{thread_ts}"
        # @param after [String, nil] only messages after this ts are returned
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def fetch_thread_history(channel_id:, thread_key:, after: nil)
          params = { channel: channel_id, ts: thread_key.split(":", 2).last,
                     inclusive: false, limit: HISTORY_PAGE_LIMIT }
          params[:oldest] = after if after.present?
          raw_messages = []
          cursor = nil
          loop do
            page_params = cursor ? params.merge(cursor: cursor) : params
            body = api_call("conversations.replies", token: settings.bot_token, params: page_params)
            raw_messages.concat(body["messages"] || [])
            cursor = body.dig("response_metadata", "next_cursor").presence
            break unless cursor
          end
          history_messages(raw_messages)
        end

        # Reads the top-level messages of a channel (or DM) through
        # conversations.history. Thread replies are not part of the result,
        # which is exactly the "top-level messages" the import asks for.
        # @param channel_id [String] the Slack channel id (DM channel for DMs)
        # @param before [String] only messages before this ts are returned
        # @param since [Time] only messages posted after this time
        # @param limit [Integer] maximum number of messages
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def fetch_channel_history(channel_id:, before:, since:, limit:)
          params = { channel: channel_id, oldest: since.to_f, inclusive: false, limit: limit }
          params[:latest] = before if before.present?
          body = api_call("conversations.history", token: settings.bot_token, params: params)
          history_messages(body["messages"] || [])
        end

        # Marks a SlackApiError as a fatal configuration/credential error so
        # the gateway exits cleanly (exit 0) and is not restarted by the
        # supervisor into the same broken configuration (ADR-006).
        # @param error [Exception] the error raised by the adapter
        # @return [Boolean]
        def fatal_config_error?(error)
          error.is_a?(SlackApiError)
        end

        private

        # Whether #stop has been called.
        def stopped?
          @stopped
        end

        # Fetches the bot's own user id and validates the bot token. The bot id
        # is kept as well: the gateway's own posts appear in the history with a
        # bot_id rather than a user id.
        # @return [String]
        def fetch_bot_user_id
          body = api_call("auth.test", token: settings.bot_token)
          @bot_id = body["bot_id"]
          body["user_id"]
        end

        # Opens a Socket Mode connection URL with the app-level token.
        # ok:false raises SlackApiError and terminates the adapter (no retry
        # for credential problems).
        # @return [String] the wss:// URL
        def open_connection_url
          api_call("apps.connections.open", token: settings.app_token)["url"]
        end

        # Connects the WebSocket and blocks until the connection ends, a
        # reconnect is requested, or the adapter is stopped.
        def listen(url)
          @connection_ended = Queue.new
          @reconnect_requested = false
          @connected = false
          @missed_pongs = 0
          adapter = self
          @ws = WebSocket::Client::Simple.connect(url) do |ws|
            ws.on(:message) do |msg|
              case msg.type
              when :text
                adapter.handle_envelope(msg.data)
              when :pong
                adapter.send(:handle_pong)
              end
            end
            ws.on(:close) { |_event| adapter.send(:connection_ended!) }
            ws.on(:error) { |error| adapter.send(:socket_errored, error) }
          end
          ping_loop
        ensure
          close_socket
        end

        # Sends pings on a fixed interval until the connection ends. Missed
        # pongs beyond the threshold force a reconnect.
        def ping_loop
          until stopped? || @reconnect_requested
            break if self.class.timed_queue_pop(@connection_ended, PING_INTERVAL_SECONDS)
            if ping_tick
              ai_helper_logger.warn "slack: #{MAX_MISSED_PONGS} pongs missed, reconnecting"
              request_reconnect
              break
            end
            @ws&.send("ping", type: :ping)
          end
        end

        # Counts a sent ping without a pong reply yet. Returns true when the
        # missed-pong threshold is exceeded and the connection should be
        # dropped.
        # @return [Boolean]
        def ping_tick
          @missed_pongs += 1
          @missed_pongs > MAX_MISSED_PONGS
        end

        # A pong arrived: the connection is healthy.
        def handle_pong
          @missed_pongs = 0
          ai_helper_logger.debug "slack: pong received"
        end

        # Asks the listen loop to end so #start reconnects with a fresh URL.
        def request_reconnect
          @reconnect_requested = true
          @connection_ended&.push(true)
        end

        # The socket was closed by the remote side.
        def connection_ended!
          @connection_ended&.push(true)
        end

        # A socket error occurred; end the connection so #start can retry.
        def socket_errored(error)
          ai_helper_logger.error "slack: websocket error: #{error.message}"
          @connection_ended&.push(true)
        end

        def close_socket
          socket = @ws
          @ws = nil
          socket&.close
        rescue IOError, SystemCallError => e
          ai_helper_logger.debug "slack: error while closing socket: #{e.message}"
        end

        # Returns the current backoff delay and doubles it (capped).
        # @return [Integer] seconds to wait
        def next_backoff
          current = @backoff
          @backoff = [ @backoff * 2, MAX_BACKOFF_SECONDS ].min
          current
        end

        # Resets the backoff after a successful connection.
        def reset_backoff
          @backoff = 1
        end

        # Sends the events_api ack immediately so Slack does not resend the
        # event.
        def acknowledge(envelope_id)
          @ws&.send({ envelope_id: envelope_id }.to_json)
        end

        # Converts a Slack event into an IncomingMessage and dispatches it.
        # Bot messages, the bot's own messages and subtyped events (edits,
        # deletions) are discarded to avoid loops.
        def process_event(event)
          return if event["bot_id"].present?
          return if event["subtype"].present?
          return if event["user"].blank? || event["user"] == @bot_user_id

          dm = event["type"] == "message" && event["channel_type"] == "im"
          return unless dm || event["type"] == "app_mention"

          thread_ts = event["thread_ts"].presence || event["ts"]
          dispatch(IncomingMessage.new(
            channel_type: channel_type,
            channel_id: event["channel"],
            thread_key: "#{event["channel"]}:#{thread_ts}",
            message_ts: event["ts"],
            text: strip_mention(event["text"].to_s),
            dm: dm,
            in_thread: event["thread_ts"].present?
          ))
        end

        # Removes the bot mention markup from the question text.
        def strip_mention(text)
          text.gsub(/<@#{Regexp.escape(@bot_user_id.to_s)}>/, "").strip
        end

        # Converts raw Slack messages into history messages, dropping the ones
        # that must not be imported (FR-009) and restoring ascending order:
        # Slack answers newest first.
        # @param raw_messages [Array<Hash>] the raw message objects
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def history_messages(raw_messages)
          raw_messages.reverse.filter_map { |raw| history_message(raw) }
        end

        # Converts one raw message, or nil when it must not be imported.
        # @param raw [Hash] the raw message object
        # @return [HistoryMessage, nil]
        def history_message(raw)
          return nil unless HISTORY_SUBTYPES.include?(raw["subtype"])
          return nil if own_message?(raw)

          text = raw["text"].to_s
          return nil if mentions_bot?(text)

          text = text.strip
          return nil if text.empty?

          HistoryMessage.new(speaker: speaker_name(raw), text: text)
        end

        # Whether the message was posted by the gateway itself, either as the
        # bot user or through the app's bot identity.
        # @param raw [Hash] the raw message object
        # @return [Boolean]
        def own_message?(raw)
          return true if @bot_user_id.present? && raw["user"] == @bot_user_id

          @bot_id.present? && raw["bot_id"] == @bot_id
        end

        # Whether the text addresses the bot, which means it is already stored
        # as the question of this or another conversation.
        # @param text [String] the message body
        # @return [Boolean]
        def mentions_bot?(text)
          text.include?("<@#{@bot_user_id}>")
        end

        # The speaker's display name. Messages of other bots carry their name
        # in the payload, so they need no users.info lookup.
        # @param raw [Hash] the raw message object
        # @return [String]
        def speaker_name(raw)
          if raw["bot_id"].present?
            raw["username"].presence || raw.dig("bot_profile", "name").presence || raw["bot_id"]
          else
            user_display_name(raw["user"])
          end
        end

        # Resolves a user id to a display name, caching the result for the
        # lifetime of the adapter so repeated mentions in the same thread do
        # not call users.info again.
        # @param user_id [String, nil] the Slack user id
        # @return [String]
        def user_display_name(user_id)
          return user_id.to_s if user_id.blank?

          cached = @display_names[user_id]
          return cached if cached

          profile = api_call("users.info", token: settings.bot_token, params: { user: user_id })["user"] || {}
          name = profile.dig("profile", "display_name").presence ||
                 profile["real_name"].presence || profile["name"].presence || user_id
          cache_display_name(user_id, name)
          name
        end

        # Stores a display name, evicting the oldest entry once the cap is
        # exceeded (FIFO).
        # @param user_id [String] the Slack user id
        # @param name [String] the resolved display name
        # @return [void]
        def cache_display_name(user_id, name)
          @display_names.delete(user_id)
          @display_names[user_id] = name
          @display_names.delete(@display_names.each_key.first) while @display_names.size > MAX_DISPLAY_NAMES
        end

        # Splits a reply into chunks within the Slack message limit,
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

        # Calls a Slack Web API method. ok:false responses are raised as
        # SlackApiError and never swallowed (FR-011). The token itself is
        # never logged.
        # @param method [String] API method name (e.g. "auth.test")
        # @param token [String] Bearer token for the call
        # @param params [Hash] form parameters
        # @return [Hash] the parsed response body
        def api_call(method, token:, params: {})
          uri = URI("#{SLACK_API_BASE}/#{method}")
          request = Net::HTTP::Post.new(uri.path)
          request["Authorization"] = "Bearer #{token}"
          request.set_form_data(params) unless params.empty?
          response = build_http(uri).request(request)
          body = JSON.parse(response.body)
          raise SlackApiError, "Slack API #{method} failed: #{body["error"]}" unless body["ok"]
          body
        end
      end
    end
  end
end
