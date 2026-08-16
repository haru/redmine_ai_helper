# frozen_string_literal: true

require "json"
require "jwt"
require "net/http"
require "time"
require "uri"
require "redmine_ai_helper/chat_channel/inbound_adapter"
require "redmine_ai_helper/chat_channel/history_message"

module RedmineAiHelper
  module ChatChannel
    module Adapters
      # Microsoft Teams adapter. Teams delivers activities to a public HTTPS
      # endpoint instead of offering an outgoing connection, so this adapter
      # inherits the inbound queue polling of InboundAdapter and only
      # implements the Teams-specific parts: Bot Framework JWT verification,
      # activity normalization, replies through the Bot Connector REST API and
      # surrounding-message import through Microsoft Graph.
      #
      # The settings columns are reused with Teams meanings: +app_token+ is the
      # Microsoft App ID, +bot_token+ the client secret and +tenant_id+ the
      # organization allowed to reach this integration, which is also the
      # directory the bot's single-tenant credentials live in. The secrets among
      # them -- the client secret and the access tokens obtained with it -- are
      # never written to the log or to an exception message. The tenant is not a
      # secret and does appear in both: a rejected activity is logged with the
      # tenant that sent it, and the tenant is part of the token endpoint URL
      # that request logging prints.
      class TeamsAdapter < InboundAdapter
        # Raised on authentication/configuration failures (Bot Connector or
        # Graph 401/403, token endpoint 400/401). Classified as a fatal config
        # error so the gateway does not retry into the same broken credentials
        # (ADR-006). Credential values never appear here.
        class TeamsApiError < StandardError; end

        # Raised on non-authentication API failures (404, other 4xx, exhausted
        # 429/5xx retries). Carries the HTTP status so callers can react to
        # specific conditions.
        class TeamsRequestError < StandardError
          # @return [Integer, nil] the HTTP status code
          attr_reader :status

          # @param message [String] human-readable error (never a credential)
          # @param status [Integer, nil] HTTP status code
          def initialize(message, status: nil)
            super(message)
            @status = status
          end
        end

        # Open/read timeout for every HTTP call (contract: 10 seconds).
        HTTP_TIMEOUT_SECONDS = 10

        # OpenID metadata document naming the current signing keys (E-2).
        OPENID_METADATA_URL = "https://login.botframework.com/v1/.well-known/openidconfiguration"

        # The only signing algorithm the Bot Framework announces.
        TOKEN_SIGNING_ALGORITHM = "RS256"

        # The issuer every genuine Bot Framework token carries.
        BOT_FRAMEWORK_ISSUER = "https://api.botframework.com"

        # Allowed difference between this server's clock and the token's
        # lifetime bounds (E-7).
        CLOCK_SKEW_SECONDS = 300

        # How long the fetched signing keys are reused before they are read
        # again (E-2).
        JWKS_CACHE_SECONDS = 24 * 60 * 60

        # Entra ID host issuing the client-credentials tokens.
        LOGIN_HOST = "https://login.microsoftonline.com"

        # The scope of the client-credentials request per audience
        # (contracts/teams_external_apis.md E-3). Both tokens are issued by the
        # configured tenant, so the scope is all that separates them.
        TOKEN_SCOPES = {
          connector: "https://api.botframework.com/.default",
          graph: "https://graph.microsoft.com/.default"
        }.freeze

        # A cached access token is renewed this many seconds before it expires.
        TOKEN_EXPIRY_MARGIN_SECONDS = 60

        # First wait of the retry backoff; doubled on every further attempt
        # (1s, 2s, 4s) unless the response names its own Retry-After.
        RETRY_BACKOFF_BASE_SECONDS = 1

        # Base URL of the Microsoft Graph API (v1.0).
        GRAPH_BASE_URL = "https://graph.microsoft.com/v1.0"

        # Every team channel identifier starts with this; a one-to-one chat
        # conversation does not.
        TEAMS_CHANNEL_ID_PREFIX = "19:"

        # Replies requested per page when reading a thread (Graph maximum).
        THREAD_PAGE_SIZE = 50

        # Upper bound on the cached team id to group id pairs (R-013).
        MAX_CACHED_TEAMS = 100

        # Speaker name used when Graph does not name the sender, so the
        # imported messages stay attributable to distinct speakers (INV-T16).
        UNKNOWN_SPEAKER = "(unknown)"

        # A one-to-one chat conversation ends after this many hours without a
        # message; the next question starts a new one (FR-018a).
        PERSONAL_SESSION_HOURS = 24

        # How many times a throttled or temporarily failing call is repeated
        # before it is given up on. Every call the adapter makes - posting an
        # answer, resolving a team, reading history - runs on the single
        # worker thread that processes answers, so retrying without a bound
        # would hold up every later question (R-010).
        MAX_API_RETRIES = 3

        # Upper bound on one wait between retries. Teams can name a
        # Retry-After of several minutes; honouring that unchanged would stop
        # the worker for as long as the server asks, so a longer request is
        # capped and the retry budget runs out instead of the worker standing
        # still (R-010).
        MAX_RETRY_DELAY_SECONDS = 60

        # Replies longer than this are split before posting. Teams accepts
        # roughly 28KB per message; 6,000 characters stay well inside that even
        # for multi-byte text (research.md R-011).
        MAX_MESSAGE_LENGTH = 6000

        # Teams renders markdown link syntax in message bodies. Defined here
        # rather than in IssueLinkFormatter so no shared file changes for this
        # adapter (research.md R-011, INV-T20).
        MARKDOWN_LINK_FORMAT = IssueLinkFormatter::Format.new(
          ->(label, url) { "[#{label}](#{url})" },
          /\[#\d+\]\(https?:\/\/[^\s)]+\)/
        ).freeze

        # The Bot Framework signing keys and when they were read. Held on the
        # class rather than on an instance because #verify_request runs in the
        # Redmine web process, which builds a new adapter for every delivery:
        # an instance-level cache would be rebuilt on every request and
        # JWKS_CACHE_SECONDS would never take effect. The keys are the public
        # document Microsoft publishes for everyone, so nothing belonging to
        # one integration is shared by putting them here (INV-T5).
        @jwks = nil
        @jwks_fetched_at = nil
        @jwks_mutex = Mutex.new

        class << self
          # @return [String] the adapter identifier
          def channel_type
            "teams"
          end

          # The cached signing keys, read through the given block when the
          # cache is empty, stale, or explicitly refreshed. The lock is held
          # across the read so that concurrent deliveries arriving on a cold
          # cache wait for one read instead of each starting its own; a read
          # that raises caches nothing and the next delivery tries again.
          # @param refresh [Boolean] read the keys again even when cached
          # @yieldreturn [Hash] the freshly read JWKS document
          # @return [Hash] the JWKS document
          def cached_jwks(refresh: false)
            @jwks_mutex.synchronize do
              @jwks = nil if refresh
              @jwks = nil if @jwks_fetched_at && (monotonic_now - @jwks_fetched_at) >= JWKS_CACHE_SECONDS
              unless @jwks
                @jwks = yield
                @jwks_fetched_at = monotonic_now
              end
              @jwks
            end
          end

          # Empties the signing key cache. A running process never needs this
          # - it rotates the keys through .cached_jwks itself - but a test
          # asserting how often the keys are read must start from a known
          # state, which a cache outliving the instance no longer gives it.
          # @return [void]
          def reset_jwks_cache
            @jwks_mutex.synchronize do
              @jwks = nil
              @jwks_fetched_at = nil
            end
          end

          # The monotonic clock the caches are timed against.
          # @return [Float] seconds
          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          # The Microsoft App ID, the client secret and the organization
          # (tenant) allowed to reach this integration. This declaration is the
          # single source of truth for the settings form and for the
          # enable-time validation (INV-T1).
          # @return [Array<Symbol>]
          def required_setting_fields
            [ :app_token, :bot_token, :tenant_id ]
          end
        end

        # Sets up the caches this instance owns. They are deliberately
        # in-memory only: an access token and a team's group id are both
        # derivable again at any time, so nothing here belongs in the database
        # (data-model.md 5). Both are read only by the resident gateway
        # process, whose adapter lives for the whole run; the signing keys the
        # per-delivery web process needs are cached on the class instead.
        # @return [void]
        def initialize
          super
          @access_tokens = {}
          @aad_group_ids = {}
        end

        # Whether the delivery really comes from the Bot Framework, on behalf
        # of this bot, for the organization this integration is configured for
        # (C-1). Returning false makes the shared endpoint answer 401 without
        # storing anything.
        #
        # The signature is checked on the token from the Authorization header;
        # the body is parsed only to compare the serviceUrl and the tenant with
        # what the token claims (INV-T2). A body that cannot be parsed is not
        # accepted, because neither comparison could then be made.
        #
        # Being unable to read the signing keys is not a refusal and is
        # deliberately not turned into one: answering 401 would tell Teams to
        # drop the delivery for good, while letting the error reach the
        # endpoint answers 5xx and Teams delivers the message again once
        # Microsoft's key endpoint is reachable.
        # @param request [ActionDispatch::Request] the received delivery
        # @raise [TeamsRequestError] when the signing keys cannot be read
        # @return [Boolean]
        def verify_request(request)
          token = bearer_token(request)
          return reject("no bearer token in the Authorization header") if token.blank?

          activity = parse_body(request)
          return reject("the request body is not a JSON object") if activity.nil?

          claims = verified_claims(token)
          return false if claims.nil?
          return reject("the serviceUrl claim does not match the activity") unless service_url_matches?(claims, activity)

          tenant_allowed?(activity)
        end

        # Converts one verified delivery into the question it carries, or into
        # nothing at all when the activity is not a question for this bot
        # (C-2). An activity that cannot be interpreted raises: the shared
        # endpoint records it and still answers 200, so a malformed delivery is
        # neither retried forever nor silently dropped (INV-T10 / FR-010).
        # @param request [ActionDispatch::Request] the verified delivery
        # @return [Array<Hash>] zero or one normalized event
        def parse_events(request)
          activity = JSON.parse(request.raw_post)
          raise ArgumentError, "teams: the activity is not a JSON object" unless activity.is_a?(Hash)
          return [] unless question_activity?(activity)

          case activity.dig("conversation", "conversationType")
          when "channel" then channel_event(activity)
          when "personal" then personal_event(activity)
          else
            ai_helper_logger.info "teams: ignored an activity of conversation type " \
                                  "#{activity.dig("conversation", "conversationType").inspect}"
            []
          end
        end

        # Posts a reply into the conversation the question came from, split
        # into as many messages as the Teams size limit requires (C-3).
        #
        # The destination is taken from what was stored when the question was
        # received, never rebuilt from the thread key: a one-to-one thread key
        # carries a session marker and is not a conversation id (INV-T11).
        # @param channel_id [String] the channel the conversation is bound to
        #   (unused: the stored conversation id is the destination)
        # @param thread_key [String] the thread being replied to
        # @param text [String] the reply body
        # @return [void]
        def send_message(channel_id:, thread_key:, text:) # rubocop:disable Lint/UnusedMethodArgument
          metadata = reply_metadata_for(thread_key: thread_key)
          if metadata.blank?
            raise TeamsRequestError, "teams: no reply destination is stored for the conversation being answered"
          end

          service_url = require_field(metadata["service_url"], "reply_metadata.service_url")
          conversation_id = require_field(metadata["conversation_id"], "reply_metadata.conversation_id")
          uri = URI("#{service_url.chomp("/")}/v3/conversations/#{conversation_id}/activities")
          split_text(text).each do |chunk|
            api_request(:post, uri, audience: :connector, body: { type: "message", text: chunk })
          end
        end

        # Teams keeps the messages around a question in the channel, and
        # Microsoft Graph serves them to a bot that was granted the
        # ChannelMessage.Read.Group resource-specific consent (R-012).
        # @return [Boolean]
        def supports_history?
          true
        end

        # The messages posted in a channel thread, oldest first (C-4). The
        # thread's own root message is included only on the first import, when
        # there is no cursor to continue from.
        # @param channel_id [String] the channel the thread lives in
        # @param thread_key [String] the conversation id of the thread
        # @param after [String, nil] only messages after this message id
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def fetch_thread_history(channel_id:, thread_key:, after: nil)
          return [] if personal_conversation?(channel_id)

          root_id = require_field(thread_root_id(thread_key), "thread root id")
          base = "#{graph_channel_url(channel_id)}/messages/#{root_id}"
          raw = after.blank? ? [ graph_get(URI(base)) ] : []
          raw.concat(graph_pages(URI("#{base}/replies?$top=#{THREAD_PAGE_SIZE}")))
          history_messages(raw.select { |message| after.blank? || message["id"].to_i > after.to_i })
        end

        # The most recent top-level messages of a channel, oldest first (C-4).
        # Graph orders channel messages by the last activity of their reply
        # chain rather than by creation, so the page is filtered and reordered
        # here.
        # @param channel_id [String] the channel to read
        # @param before [String] only messages before this message id
        # @param since [Time] only messages posted at or after this time
        # @param limit [Integer] maximum number of messages to request
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def fetch_channel_history(channel_id:, before:, since:, limit:)
          return [] if personal_conversation?(channel_id)

          page = graph_get(URI("#{graph_channel_url(channel_id)}/messages?$top=#{limit}"))["value"]
          history_messages(Array(page).select do |message|
            posted = posted_at(message)
            message["id"].to_i < before.to_i && posted && posted >= since
          end)
        end

        # @return [IssueLinkFormatter::Format]
        def issue_link_format
          MARKDOWN_LINK_FORMAT
        end

        # Classifies TeamsApiError as a fatal configuration/credential error so
        # the gateway exits cleanly rather than retrying broken credentials
        # (ADR-006 / C-7).
        # @param error [Exception] the error raised by the adapter
        # @return [Boolean]
        def fatal_config_error?(error)
          error.is_a?(TeamsApiError)
        end

        private

        # The token of an +Authorization: Bearer <token>+ header, or nil when
        # the header is absent or has another scheme.
        # @param request [ActionDispatch::Request] the received delivery
        # @return [String, nil]
        def bearer_token(request)
          request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
        end

        # The request body parsed as an activity, or nil when it is not a JSON
        # object. Broken JSON is rejected here rather than raised: a delivery
        # whose tenant cannot even be read must never be accepted (C-1).
        # @param request [ActionDispatch::Request] the received delivery
        # @return [Hash, nil]
        def parse_body(request)
          parsed = JSON.parse(request.raw_post)
          parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError
          nil
        end

        # The verified claims of the Bot Framework token, or nil when it fails
        # verification. Every check the Bot Connector documentation requires is
        # applied: RS256 with a key from the published JWKS, the Bot Framework
        # issuer, this bot as the audience, and a currently valid lifetime
        # (300s of allowed clock skew).
        # @param token [String] the bearer token
        # @return [Hash, nil] the payload, or nil when verification failed
        def verified_claims(token)
          payload, = JWT.decode(
            token, nil, true,
            algorithms: [ TOKEN_SIGNING_ALGORITHM ],
            jwks: jwks_loader,
            iss: BOT_FRAMEWORK_ISSUER, verify_iss: true,
            aud: app_id, verify_aud: true,
            verify_expiration: true, verify_not_before: true,
            leeway: CLOCK_SKEW_SECONDS
          )
          payload
        rescue JWT::DecodeError => e
          # The message names the failed check (signature, aud, iss, exp, ...)
          # and never contains a credential: JWT builds it from the claim
          # names alone.
          reject("token verification failed: #{e.message}")
          nil
        end

        # The loader the JWT gem resolves signing keys through. The keys are
        # cached on the class for JWKS_CACHE_SECONDS; an unknown key id makes
        # the gem call this a second time with kid_not_found, which reads them
        # again immediately so a key rotation does not reject every delivery
        # until the cache expires (INV-T5).
        # @return [Proc]
        def jwks_loader
          lambda do |options|
            self.class.cached_jwks(refresh: options[:kid_not_found].present?) { fetch_jwks }
          end
        end

        # Reads the current signing keys through the Bot Framework OpenID
        # metadata document, which names the JWKS location (E-2).
        # @return [Hash] the JWKS document
        def fetch_jwks
          metadata = fetch_public_json(URI(OPENID_METADATA_URL))
          fetch_public_json(URI(metadata.fetch("jwks_uri")))
        end

        # Performs one unauthenticated GET and returns the parsed JSON body.
        # Used for the Microsoft-published documents that carry no secret.
        # @param uri [URI] the request URI
        # @return [Hash] the parsed body
        def fetch_public_json(uri)
          response = build_http(uri).request(Net::HTTP::Get.new(uri.request_uri))
          code = response.code.to_i
          unless (200..299).cover?(code)
            raise TeamsRequestError.new("teams: GET #{uri} failed: HTTP #{code}", status: code)
          end

          parse_json_body(response)
        end

        # Whether the token was issued for the host the activity says answers
        # belong to. Without this check a token captured from one organization
        # could make the bot post to another host (R-002); a token that does
        # not carry the claim at all fails the comparison.
        # @param claims [Hash] the verified token payload
        # @param activity [Hash] the received activity
        # @return [Boolean]
        def service_url_matches?(claims, activity)
          claims["serviceUrl"].present? && claims["serviceUrl"] == activity["serviceUrl"]
        end

        # Whether the activity comes from the organization this integration is
        # configured for (FR-008a). This comparison is the only gate between a
        # genuinely signed request from another organization and the queue
        # (ADR-018 decision 1), so a blank configured tenant refuses rather
        # than matching the activity that names no tenant either. The tenant
        # identifier is not a credential, so a mismatch is logged with both
        # values.
        # @param activity [Hash] the received activity
        # @return [Boolean]
        def tenant_allowed?(activity)
          return reject("no tenant is configured for this integration") if configured_tenant_id.blank?

          tenant = activity.dig("channelData", "tenant", "id").presence ||
                   activity.dig("conversation", "tenantId").presence
          return true if tenant == configured_tenant_id

          reject("tenant #{tenant.inspect} is not the configured tenant #{configured_tenant_id.inspect}")
        end

        # The Microsoft App ID of this integration. Read from the settings row
        # once per adapter: #verify_request would otherwise read the row twice
        # for every delivery, and a history import once for every imported
        # message. Changing it takes a gateway restart either way, which the
        # settings screen states.
        # @return [String, nil]
        def app_id
          @app_id ||= settings.app_token
        end

        # The organization this integration accepts activities from, read once
        # per adapter for the same reason as #app_id.
        # @return [String, nil]
        def configured_tenant_id
          @configured_tenant_id ||= settings.tenant_id
        end

        # Records why a delivery was refused and answers false. The reason
        # never leaves the log: the endpoint replies 401 with no body, so a
        # caller cannot probe which check failed (INV-T4).
        # @param reason [String] why the delivery was refused
        # @return [false]
        def reject(reason)
          ai_helper_logger.warn "teams: rejected an inbound request (#{reason})"
          false
        end

        # Whether the identifier names a one-to-one chat rather than a team
        # channel. Only team channels have messages of their own to import: a
        # one-to-one chat holds nothing but the questions and answers already
        # stored in Redmine, and Graph is not called for it at all (INV-T15).
        # @param channel_id [String] the channel identifier of a message
        # @return [Boolean]
        def personal_conversation?(channel_id)
          !channel_id.to_s.start_with?(TEAMS_CHANNEL_ID_PREFIX)
        end

        # The Graph base URL of a channel. Graph addresses a team by its Entra
        # group id, which the activities do not carry, so it is resolved
        # through the Bot Connector and cached (E-5).
        # @param channel_id [String] the Teams channel id
        # @return [String] the absolute URL of the channel resource
        def graph_channel_url(channel_id)
          metadata = channel_metadata(channel_id)
          group_id = aad_group_id(require_field(metadata["team_id"], "reply_metadata.team_id"),
                                  require_field(metadata["service_url"], "reply_metadata.service_url"))
          "#{GRAPH_BASE_URL}/teams/#{group_id}/channels/#{channel_id}"
        end

        # The service_url and team_id of a channel, taken from the newest event
        # stored for it. Both describe the channel rather than one message, so
        # any of its events answers the question - which is what makes this
        # work for #fetch_channel_history too, whose arguments name no thread.
        # @param channel_id [String] the Teams channel id
        # @return [Hash] the stored reply metadata
        def channel_metadata(channel_id)
          event = AiHelperInboundEvent.where(channel_type: channel_type, channel_id: channel_id)
                                      .where.not(reply_metadata: [ nil, "" ])
                                      .order(:received_at).last
          if event.nil?
            raise TeamsRequestError, "teams: no received event names the team of channel #{channel_id}"
          end

          JSON.parse(event.reply_metadata)
        end

        # The Entra group id of a team, from the process-local cache when it
        # has been resolved before (INV-T19).
        # @param team_id [String] the team id carried by the activity
        # @param service_url [String] the Bot Connector host of the team
        # @return [String] the Entra group id
        def aad_group_id(team_id, service_url)
          cached = @aad_group_ids[team_id]
          return cached if cached

          team = api_request(:get, URI("#{service_url.chomp("/")}/v3/teams/#{team_id}"), audience: :connector)
          remember_aad_group_id(team_id, require_field(team["aadGroupId"], "aadGroupId"))
        end

        # Caches one team's group id, dropping the oldest entry once the cache
        # is full. The gateway is a resident process and an entry has no other
        # eviction path, so the cache is bounded; a dropped entry only costs
        # one lookup the next time that team is seen.
        # @param team_id [String] the team id
        # @param group_id [String] the resolved Entra group id
        # @return [String] the group id
        def remember_aad_group_id(team_id, group_id)
          @aad_group_ids.delete(team_id)
          @aad_group_ids[team_id] = group_id
          @aad_group_ids.delete(@aad_group_ids.each_key.first) while @aad_group_ids.size > MAX_CACHED_TEAMS
          group_id
        end

        # Reads one Graph resource, with the same retry budget as every other
        # call: a throttled context import would otherwise cost the answer its
        # surrounding messages where repeating the read would have worked.
        # @param uri [URI] the absolute Graph URL
        # @return [Hash] the parsed response body
        def graph_get(uri)
          api_request(:get, uri, audience: :graph)
        end

        # Reads a paged Graph collection, following the continuation links
        # until the collection is exhausted.
        # @param uri [URI] the absolute URL of the first page
        # @return [Array<Hash>] the raw messages of every page
        def graph_pages(uri)
          collected = []
          next_uri = uri
          while next_uri
            page = graph_get(next_uri)
            collected.concat(Array(page["value"]))
            next_link = page["@odata.nextLink"]
            next_uri = next_link.present? ? URI(next_link) : nil
          end
          collected
        end

        # Converts raw Graph messages into history messages in ascending id
        # order, dropping the ones that must not be imported (C-4).
        # @param raw_messages [Array<Hash>] the raw Graph messages
        # @return [Array<HistoryMessage>] ascending (oldest first)
        def history_messages(raw_messages)
          raw_messages.sort_by { |message| message["id"].to_i }
                      .filter_map { |message| history_message(message) }
        end

        # Converts one raw Graph message, or nil when it must not be imported:
        # a system event, an application's own post, a question already
        # addressed to the bot, or a body that is empty once the markup is
        # gone.
        # @param raw [Hash] the raw Graph message
        # @return [HistoryMessage, nil]
        def history_message(raw)
          return nil unless raw["messageType"] == "message"
          return nil if raw.dig("from", "application").present? || raw.dig("from", "user").blank?
          return nil if mentions_bot?(raw)

          text = plain_body(raw)
          return nil if text.blank?

          HistoryMessage.new(speaker: raw.dig("from", "user", "displayName").presence || UNKNOWN_SPEAKER,
                             text: text)
        end

        # When a raw Graph message was posted, or nil when it carries no
        # readable timestamp. Nil rather than raising, so that one unreadable
        # message is dropped the way every other unusable message is instead
        # of failing the import of the whole page.
        # @param raw [Hash] the raw Graph message
        # @return [Time, nil]
        def posted_at(raw)
          Time.iso8601(raw["createdDateTime"].to_s)
        rescue ArgumentError
          nil
        end

        # Whether the message addresses the bot. Such a message is a question
        # this integration already stored as part of a conversation, so
        # importing it again would duplicate it (C-4).
        # @param raw [Hash] the raw Graph message
        # @return [Boolean]
        def mentions_bot?(raw)
          Array(raw["mentions"]).any? do |mention|
            mention.dig("mentioned", "application", "id") == app_id
          end
        end

        # The message body as plain text: Teams stores most bodies as HTML,
        # and the imported context is prose for the LLM, not markup (INV-T17).
        # The entities an HTML body escapes are resolved too, so the text
        # reads as the speaker wrote it.
        # @param raw [Hash] the raw Graph message
        # @return [String]
        def plain_body(raw)
          content = raw.dig("body", "content").to_s
          if raw.dig("body", "contentType") == "html"
            content = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(content))
          end
          content.strip
        end

        # Splits a reply into chunks within the Teams message limit,
        # preferring paragraph boundaries, then line boundaries, then a hard
        # cut, and never cutting inside an issue link. No content is dropped.
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
            cut = link_safe_cut(remaining, cut)
            chunks << remaining[0, cut]
            remaining = remaining[cut..].to_s.sub(/\A\n+/, "")
          end
          chunks << remaining unless remaining.empty?
          chunks
        end

        # Whether the activity is a message from someone other than the bot
        # itself. Everything else (typing indicators, membership changes, the
        # bot's own posts) is not a question and is only logged (C-2).
        # @param activity [Hash] the received activity
        # @return [Boolean]
        def question_activity?(activity)
          unless activity["type"] == "message"
            ai_helper_logger.debug "teams: ignored a #{activity["type"].inspect} activity"
            return false
          end

          if activity.dig("from", "id") == bot_user_id
            ai_helper_logger.debug "teams: ignored the bot's own message"
            return false
          end

          true
        end

        # The bot's own identifier in Teams, which is always its app id with
        # the bot prefix - no API call is needed to learn it (R-004).
        # @return [String]
        def bot_user_id
          "28:#{app_id}"
        end

        # The event for a message posted in a team channel, or none when the
        # bot was not addressed. The conversation id already identifies the
        # thread the question belongs to, so it is the thread key as-is (R-006).
        # @param activity [Hash] the received activity
        # @return [Array<Hash>] zero or one normalized event
        def channel_event(activity)
          mentions = own_mentions(activity)
          if mentions.empty?
            ai_helper_logger.debug "teams: ignored a channel message that does not mention the bot"
            return []
          end

          text = strip_mentions(activity, mentions)
          if text.blank?
            ai_helper_logger.info "teams: ignored a mention with no question text"
            return []
          end

          conversation_id = require_field(activity.dig("conversation", "id"), "conversation.id")
          message_id = require_field(activity["id"], "id")
          [ {
            event_key: "#{conversation_id}:#{message_id}",
            text: text,
            channel_id: require_field(activity.dig("channelData", "channel", "id"), "channelData.channel.id"),
            thread_key: conversation_id,
            message_ts: message_id,
            dm: false,
            in_thread: message_id != thread_root_id(conversation_id),
            reply_metadata: reply_metadata(activity, conversation_id,
                                           team_id: activity.dig("channelData", "team", "id"))
          } ]
        end

        # The event for a message sent directly to the bot. No mention is
        # required there: every message is a question (C-2).
        # @param activity [Hash] the received activity
        # @return [Array<Hash>] zero or one normalized event
        def personal_event(activity)
          text = activity["text"].to_s.strip
          if text.blank?
            ai_helper_logger.info "teams: ignored a direct message with no question text"
            return []
          end

          conversation_id = require_field(activity.dig("conversation", "id"), "conversation.id")
          message_id = require_field(activity["id"], "id")
          [ {
            event_key: "#{conversation_id}:#{message_id}",
            text: text,
            channel_id: conversation_id,
            thread_key: personal_thread_key(conversation_id),
            message_ts: message_id,
            dm: true,
            in_thread: false,
            reply_metadata: reply_metadata(activity, conversation_id)
          } ]
        end

        # The thread key of a one-to-one chat. Teams has no threads there, so
        # a conversation is delimited by time instead: a question asked within
        # PERSONAL_SESSION_HOURS of the previous one continues it, and a later
        # one starts a new session (FR-018a).
        #
        # The decision is made from the stored events alone - read, never
        # written (INV-T9) - so it survives a gateway restart, and it is fixed
        # in the thread key at receive time so a delayed answer cannot move the
        # boundary.
        # @param conversation_id [String] the one-to-one conversation id
        # @return [String]
        def personal_thread_key(conversation_id)
          latest = AiHelperInboundEvent.where(channel_type: channel_type, channel_id: conversation_id)
                                       .order(:received_at).last
          return latest.thread_key if latest && latest.received_at >= PERSONAL_SESSION_HOURS.hours.ago

          "#{conversation_id}#s=#{Time.current.to_i}"
        end

        # Where a reply to this activity has to be posted, and the team the
        # channel belongs to. Kept apart from the thread key because a
        # one-to-one thread key is not a conversation id (INV-T11), and
        # deliberately free of anything identifying the speaker (INV-T6).
        # @param activity [Hash] the received activity
        # @param conversation_id [String] the conversation to reply into
        # @param team_id [String, nil] the team the channel belongs to
        # @return [Hash]
        def reply_metadata(activity, conversation_id, team_id: nil)
          {
            service_url: require_field(activity["serviceUrl"], "serviceUrl"),
            conversation_id: conversation_id,
            team_id: team_id
          }.compact
        end

        # The mention entities addressing this bot. Matching is done on the
        # entities rather than on the text, which the sender controls, and only
        # the bot's own mentions are collected so mentions of other people stay
        # part of the question (INV-T8 / R-005).
        # @param activity [Hash] the received activity
        # @return [Array<Hash>]
        def own_mentions(activity)
          recipient_id = activity.dig("recipient", "id")
          return [] if recipient_id.blank?

          Array(activity["entities"]).select do |entity|
            entity.is_a?(Hash) && entity["type"] == "mention" &&
              entity.dig("mentioned", "id") == recipient_id
          end
        end

        # The question text with the bot's own mention markup removed and the
        # whitespace it leaves behind collapsed.
        # @param activity [Hash] the received activity
        # @param mentions [Array<Hash>] the bot's own mention entities
        # @return [String]
        def strip_mentions(activity, mentions)
          text = activity["text"].to_s
          mentions.each do |mention|
            markup = mention["text"].to_s
            text = text.gsub(markup, "") if markup.present?
          end
          text.gsub(/\s+/, " ").strip
        end

        # The id of the message a channel conversation started from, which the
        # conversation id carries as its messageid parameter.
        # @param conversation_id [String] the conversation id
        # @return [String, nil]
        def thread_root_id(conversation_id)
          conversation_id[/;messageid=(.+)\z/, 1]
        end

        # Returns the value, or raises when the activity does not carry it. A
        # missing field means the payload is not the activity it claims to be,
        # which must surface rather than be stored as a half-built event
        # (INV-T10).
        # @param value [Object] the value read from the activity
        # @param name [String] the field's path, for the error message
        # @return [Object] the value
        def require_field(value, name)
          raise ArgumentError, "teams: the activity is missing #{name}" if value.blank?

          value
        end

        # A valid access token for the given audience, from the process-local
        # cache when one is still valid (INV-T13). The two audiences are cached
        # separately: they are issued by different Entra ID endpoints and are
        # not interchangeable.
        # @param audience [Symbol] :connector or :graph
        # @return [String] the bearer token
        def access_token(audience)
          cached = @access_tokens[audience]
          return cached[:token] if cached && monotonic_now < cached[:expires_at]

          fetch_access_token(audience)
        end

        # Requests a client-credentials token and caches it until
        # TOKEN_EXPIRY_MARGIN_SECONDS before it expires. Neither the
        # credentials nor the token are logged or put in an exception message
        # (INV-T21).
        # @param audience [Symbol] :connector or :graph
        # @return [String] the bearer token
        def fetch_access_token(audience)
          setting = settings
          uri = URI(token_endpoint)
          request = Net::HTTP::Post.new(uri.request_uri)
          request.set_form_data(
            "grant_type" => "client_credentials", "client_id" => setting.app_token,
            "client_secret" => setting.bot_token, "scope" => TOKEN_SCOPES.fetch(audience)
          )
          body = token_response_body(build_http(uri).request(request), audience)
          # An accepted request with no token in it is not a credential error:
          # caching the nil would send an empty Authorization header and turn
          # the next call's 401 into "your credentials are wrong", which is
          # not what happened.
          token = body["access_token"]
          raise TeamsRequestError.new("teams: the #{audience} token response carried no access token") if token.blank?

          @access_tokens[audience] = {
            token: token,
            expires_at: monotonic_now + body["expires_in"].to_i - TOKEN_EXPIRY_MARGIN_SECONDS
          }
          token
        end

        # The Entra ID token endpoint both tokens are issued by. The bot is a
        # single-tenant app, so its credentials exist only in the configured
        # organization's directory: the fixed botframework.com endpoint belongs
        # to multi-tenant bots, which Microsoft stopped registering, and it
        # rejects the credentials of a single-tenant one (E-3).
        # @return [String] the absolute URL
        def token_endpoint
          "#{LOGIN_HOST}/#{configured_tenant_id}/oauth2/v2.0/token"
        end

        # The parsed body of a token response. A rejected client credential is
        # a configuration error that must never be retried (FR-028); anything
        # else may be transient.
        # @param response [Net::HTTPResponse] the token endpoint's response
        # @param audience [Symbol] :connector or :graph
        # @return [Hash] the parsed body
        def token_response_body(response, audience)
          code = response.code.to_i
          return JSON.parse(response.body.to_s) if (200..299).cover?(code)
          raise TeamsApiError, "teams: the #{audience} token request was rejected: HTTP #{code}" if [ 400, 401 ].include?(code)

          raise TeamsRequestError.new("teams: the #{audience} token request failed: HTTP #{code}", status: code)
        end

        # Performs one authenticated Bot Connector or Microsoft Graph call and
        # returns the parsed JSON body ({} when the body is empty).
        #
        # 401/403 means the credentials or the granted permissions are wrong,
        # which no retry can fix (FR-028). 429 and 5xx are retried up to
        # +retries+ times, honouring Retry-After when the response names one;
        # every other status fails immediately. Only the method and the URL are
        # logged - never a token, a credential or a request body (FR-027).
        # @param http_method [Symbol] :get or :post
        # @param uri [URI] the absolute request URI
        # @param audience [Symbol] :connector or :graph
        # @param body [Hash, nil] the JSON body for writes
        # @param retries [Integer] how many times a throttled or failing call
        #   may be repeated
        # @return [Hash] the parsed response body
        def api_request(http_method, uri, audience:, body: nil, retries: MAX_API_RETRIES)
          attempt = 0
          loop do
            ai_helper_logger.debug "teams: #{http_method.to_s.upcase} #{uri}"
            request = build_request(http_method, uri, audience: audience, body: body)
            response = build_http(uri).request(request)
            code = response.code.to_i
            return parse_json_body(response) if (200..299).cover?(code)
            raise TeamsApiError, "teams: #{http_method.to_s.upcase} #{uri} failed: HTTP #{code}" if [ 401, 403 ].include?(code)

            unless retryable_status?(code) && attempt < retries
              raise TeamsRequestError.new("teams: #{http_method.to_s.upcase} #{uri} failed: HTTP #{code}", status: code)
            end

            delay = retry_delay(response, attempt)
            ai_helper_logger.warn "teams: #{uri} answered HTTP #{code}; retrying in #{delay}s"
            sleep(delay)
            attempt += 1
          end
        end

        # Whether the status code names a condition a repeated call may clear.
        # @param code [Integer] the HTTP status code
        # @return [Boolean]
        def retryable_status?(code)
          code == 429 || (500..599).cover?(code)
        end

        # How long to wait before repeating a call: the server's own
        # Retry-After when it names one (Teams sends it on 429), otherwise an
        # exponential backoff of 1s, 2s, 4s. Never longer than
        # MAX_RETRY_DELAY_SECONDS, however long the server asks for.
        # @param response [Net::HTTPResponse] the failed response
        # @param attempt [Integer] how many retries have already been made
        # @return [Numeric] seconds to wait
        def retry_delay(response, attempt)
          retry_after = response["Retry-After"].to_s.strip
          requested =
            if retry_after.match?(/\A\d+(\.\d+)?\z/)
              retry_after.to_f
            else
              RETRY_BACKOFF_BASE_SECONDS * (2**attempt)
            end
          [ requested, MAX_RETRY_DELAY_SECONDS ].min
        end

        # Builds a request carrying the bearer token of the given audience.
        # @param http_method [Symbol] :get or :post
        # @param uri [URI] the request URI
        # @param audience [Symbol] :connector or :graph
        # @param body [Hash, nil] the JSON body for writes
        # @return [Net::HTTPRequest]
        def build_request(http_method, uri, audience:, body: nil)
          request = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(http_method).new(uri.request_uri)
          request["Authorization"] = "Bearer #{access_token(audience)}"
          if body
            request["Content-Type"] = "application/json"
            request.body = body.to_json
          end
          request
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

        # The parsed JSON body of a successful response.
        # @param response [Net::HTTPResponse] the response
        # @return [Hash]
        def parse_json_body(response)
          response.body.to_s.empty? ? {} : JSON.parse(response.body)
        end

        # The monotonic clock reading the token cache is timed against; the
        # same one the class-level signing key cache uses.
        # @return [Float] seconds
        def monotonic_now
          self.class.monotonic_now
        end
      end
    end
  end
end
