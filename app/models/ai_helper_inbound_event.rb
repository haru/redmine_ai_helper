# frozen_string_literal: true

# One event received from an external chat service through the inbound
# webhook endpoint, normalized by the adapter at receive time. Acts as a
# persistent queue between the Redmine web process (receive) and the
# resident gateway process (poll and process): see data-model.md.
class AiHelperInboundEvent < ApplicationRecord
  # Valid values of +status+: see the state diagram in data-model.md. Declared
  # as an enum so the values live in one place instead of as string literals
  # spread over the model and the polling adapter. +validate: true+ keeps an
  # unknown value a validation error rather than an ArgumentError raised at
  # assignment time.
  STATUSES = { pending: "pending", processed: "processed", expired: "expired" }.freeze
  enum :status, STATUSES, validate: true

  validates :channel_type, :event_key, :text, :channel_id, :thread_key, :received_at, presence: true
  validates :event_key, uniqueness: { scope: :channel_type }

  class << self
    # Persists one event. The app-level uniqueness validation rejects a
    # duplicate on the normal path; the DB unique index on
    # [channel_type, event_key] is the source of truth for deduplication
    # under concurrent receives (R-004), where two inserts can both pass
    # validation before either commits.
    #
    # Only duplication is answered with nil. Any other validation failure
    # means the adapter produced an event that does not meet the
    # contracts/inbound_adapter.md event shape, which is a defect in that
    # adapter: it is raised so the caller can log it as the error it is,
    # rather than being silently folded into "already received".
    # @param attrs [Hash] channel_type:, event_key:, text:, channel_id:,
    #   thread_key:, received_at: (required), plus the optional message_ts:,
    #   dm:, in_thread:, reply_metadata:
    # @raise [ActiveRecord::RecordInvalid] when the event is invalid for any
    #   reason other than duplication
    # @return [AiHelperInboundEvent, nil] the saved event, or nil when the
    #   same channel_type/event_key was already received
    def record_event(**attrs)
      event = new(attrs)
      return event if event.save
      return nil if event.errors.of_kind?(:event_key, :taken)

      raise ActiveRecord::RecordInvalid, event
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Pending rows for the given channel_type, oldest received first.
    # @param channel_type [String] Adapter identifier
    # @param limit [Integer] Maximum number of rows to return
    # @return [ActiveRecord::Relation<AiHelperInboundEvent>]
    def pending_for(channel_type, limit:)
      pending.where(channel_type: channel_type).order(:received_at).limit(limit)
    end

    # Deletes rows of the given channel_type received before the given time
    # (FR-009). Deliberately independent of +status+: the row is kept only to
    # deduplicate resends, and a row this old can no longer be answered
    # whatever state it is in (FRESHNESS_LIMIT_SECONDS is orders of magnitude
    # shorter than the retention period).
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
    updated = self.class.pending.where(id: id).update_all(status: STATUSES[:processed])
    # rubocop:enable Rails/SkipsModelValidations
    reload if updated.positive?
    updated.positive?
  end

  # Stores the adapter's reply metadata. contracts/inbound_adapter.md lets
  # +parse_events+ return +:reply_metadata+ as a Hash while the column holds
  # JSON, so the conversion belongs here rather than in every caller: without
  # it a Hash would reach the text column and be stored as its Ruby
  # inspect form, which +InboundAdapter#reply_metadata_for+ cannot parse. A
  # String is assumed to be JSON already and is stored as given.
  # @param value [Hash, String, nil] the metadata to store
  # @return [void]
  def reply_metadata=(value)
    super(value.is_a?(Hash) ? value.to_json : value)
  end

  # Marks the row as expired (FR-008a): received too long ago to answer.
  # @return [void]
  def expire!
    expired!
  end

  # Whether +received_at+ is older than +limit_seconds+.
  # @param limit_seconds [Numeric] Freshness limit in seconds
  # @return [Boolean]
  def expired_by?(limit_seconds)
    received_at < limit_seconds.seconds.ago
  end

  # Builds the normalized message the existing chat channel core consumes.
  # Carries this row's id so that the reply posted for this message can be
  # tied back to it (InboundAdapter#reply_metadata_for); the core treats it
  # as the plain IncomingMessage it is a subclass of.
  # @return [RedmineAiHelper::ChatChannel::InboundEventMessage]
  def to_incoming_message
    RedmineAiHelper::ChatChannel::InboundEventMessage.new(
      event_id: id,
      channel_type: channel_type, channel_id: channel_id, thread_key: thread_key,
      text: text, message_ts: message_ts, dm: dm, in_thread: in_thread
    )
  end
end
