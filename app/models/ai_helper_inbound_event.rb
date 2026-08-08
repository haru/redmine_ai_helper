# frozen_string_literal: true

# One event received from an external chat service through the inbound
# webhook endpoint, normalized by the adapter at receive time. Acts as a
# persistent queue between the Redmine web process (receive) and the
# resident gateway process (poll and process): see data-model.md.
class AiHelperInboundEvent < ApplicationRecord
  # Valid values of +status+: see the state diagram in data-model.md.
  STATUSES = %w[pending processed expired].freeze

  validates :channel_type, :event_key, :text, :channel_id, :thread_key, :received_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :event_key, uniqueness: { scope: :channel_type }

  class << self
    # Persists one event. The app-level uniqueness validation rejects a
    # duplicate on the normal path; the DB unique index on
    # [channel_type, event_key] is the source of truth for deduplication
    # under concurrent receives (R-004), where two inserts can both pass
    # validation before either commits.
    # @param attrs [Hash] channel_type:, event_key:, text:, channel_id:,
    #   thread_key:, received_at: (required), plus the optional message_ts:,
    #   dm:, in_thread:, reply_metadata:
    # @return [AiHelperInboundEvent, nil] the saved event, or nil when the
    #   same channel_type/event_key was already received
    def record_event(**attrs)
      event = new(attrs)
      event.save
      event.persisted? ? event : nil
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Pending rows for the given channel_type, oldest received first.
    # @param channel_type [String] Adapter identifier
    # @param limit [Integer] Maximum number of rows to return
    # @return [ActiveRecord::Relation<AiHelperInboundEvent>]
    def pending_for(channel_type, limit:)
      where(channel_type: channel_type, status: "pending").order(:received_at).limit(limit)
    end

    # Deletes rows of the given channel_type received before the given time
    # (FR-009).
    # @param channel_type [String] Adapter identifier
    # @param before [Time] Cutoff; rows received earlier than this are deleted
    # @return [void]
    def purge_old(channel_type, before:)
      where(channel_type: channel_type, received_at: ...before).delete_all
    end
  end

  # Atomically claims this row: only a row still in +pending+ transitions to
  # +processed+ (R-004). Bypasses validations by design: this is a
  # conditional UPDATE used purely as a claim primitive (the WHERE clause,
  # not a callback, is what makes it atomic), not a write of user-provided
  # attributes. Reloads on success so the in-memory status matches the DB.
  # @return [Boolean] whether this call performed the claim
  def claim
    # rubocop:disable Rails/SkipsModelValidations
    updated = self.class.where(id: id, status: "pending").update_all(status: "processed")
    # rubocop:enable Rails/SkipsModelValidations
    reload if updated.positive?
    updated.positive?
  end

  # Marks the row as expired (FR-008a): received too long ago to answer.
  # @return [void]
  def expire!
    update!(status: "expired")
  end

  # Whether +received_at+ is older than +limit_seconds+.
  # @param limit_seconds [Numeric] Freshness limit in seconds
  # @return [Boolean]
  def expired_by?(limit_seconds)
    received_at < limit_seconds.seconds.ago
  end

  # Builds the normalized message the existing chat channel core consumes.
  # @return [RedmineAiHelper::ChatChannel::IncomingMessage]
  def to_incoming_message
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: channel_type, channel_id: channel_id, thread_key: thread_key,
      text: text, message_ts: message_ts, dm: dm, in_thread: in_thread
    )
  end
end
