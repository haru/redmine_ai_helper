# frozen_string_literal: true

# Single receive endpoint shared by every inbound chat adapter
# (+POST /ai_helper/chat_webhook/:channel_type+, contracts/webhook_endpoint.md).
# The endpoint only verifies, normalizes and persists events; it never
# generates an AI answer itself (FR-003, ADR-006 permission separation). The
# resident gateway process picks up saved rows through
# +RedmineAiHelper::ChatChannel::InboundAdapter#start+.
class AiHelperChatWebhookController < ApplicationController
  include RedmineAiHelper::Logger

  # No session is involved: the request comes from an external service, not
  # a browser with a Redmine session cookie. Authenticity is established by
  # the adapter's own #verify_request (typically a signature check), not by
  # the CSRF token.
  skip_before_action :verify_authenticity_token

  # Skip Redmine's global login_required filter so Setting.login_required =
  # ON does not return 403 before the adapter's own verification runs
  # (same reasoning as AiHelperMcpController, Issue #304).
  skip_before_action :check_if_login_required, raise: false

  # Receives one webhook delivery, verifies it, and stores zero or more
  # normalized events as pending rows for the gateway to poll
  # (contracts/webhook_endpoint.md processing order).
  # @return [void]
  def receive
    adapter = resolve_inbound_adapter
    return unless adapter

    unless adapter.verify_request(request)
      ai_helper_logger.warn "ai_helper_chat_webhook: request verification failed for channel_type=#{params[:channel_type]}"
      head :unauthorized
      return
    end

    challenge = adapter.challenge_response(request)
    if challenge
      render plain: challenge[:body], status: challenge[:status], content_type: challenge[:content_type]
      return
    end

    store_events(adapter)
    head :ok
  end

  private

  # Resolves the adapter for the requested channel_type, rendering 404 and
  # logging when it does not exist, is not an inbound adapter, or is not
  # enabled. Unknown, non-inbound and disabled adapters share the same 404
  # response so the endpoint never reveals which adapters are configured
  # (contracts/webhook_endpoint.md).
  # @return [RedmineAiHelper::ChatChannel::InboundAdapter, nil]
  def resolve_inbound_adapter
    channel_type = params[:channel_type]
    adapter_class = RedmineAiHelper::ChatChannel::BaseAdapter.adapters[channel_type]
    unless adapter_class
      ai_helper_logger.warn "ai_helper_chat_webhook: unknown channel_type=#{channel_type}"
      head :not_found
      return nil
    end

    unless adapter_class.inbound?
      ai_helper_logger.warn "ai_helper_chat_webhook: channel_type=#{channel_type} is not an inbound adapter"
      head :not_found
      return nil
    end

    adapter = adapter_class.new
    unless adapter.enabled?
      ai_helper_logger.warn "ai_helper_chat_webhook: channel_type=#{channel_type} is not enabled"
      head :not_found
      return nil
    end

    adapter
  end

  # Parses the request into events and stores each as a pending row,
  # skipping duplicates. A payload the adapter cannot interpret is logged
  # with its full backtrace and treated as received (no events stored)
  # rather than rejected, so the external service does not retry it forever
  # (contracts/webhook_endpoint.md step 6).
  # @param adapter [RedmineAiHelper::ChatChannel::InboundAdapter]
  # @return [void]
  def store_events(adapter)
    channel_type = params[:channel_type]
    events = begin
      adapter.parse_events(request)
    rescue => e
      ai_helper_logger.error "ai_helper_chat_webhook: failed to parse payload for channel_type=#{channel_type}: #{e.full_message}"
      []
    end

    events.each do |event|
      saved = AiHelperInboundEvent.record_event(channel_type: channel_type, received_at: Time.current, **event)
      ai_helper_logger.info "ai_helper_chat_webhook: duplicate event_key=#{event[:event_key]} for channel_type=#{channel_type}" unless saved
    end
  end
end
