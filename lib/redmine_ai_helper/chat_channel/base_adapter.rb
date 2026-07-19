# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/incoming_message"
require "redmine_ai_helper/chat_channel/message_handler"

module RedmineAiHelper
  module ChatChannel
    # Abstract base class for chat tool adapters. Subclasses are registered
    # automatically on inheritance (same pattern as BaseAgent) and only need
    # to implement the tool-specific interface: channel_type, start, stop,
    # send_message, resolve_user_email and notify_processing.
    class BaseAdapter
      include RedmineAiHelper::Logger

      class << self
        # Adapter subclasses collected by the inherited hook. channel_type is
        # resolved lazily in .adapters because it is not yet defined when
        # inherited fires (the subclass body has not been evaluated).
        # @return [Array<Class>]
        def registered_subclasses
          @registered_subclasses ||= []
        end

        # Registered adapter classes keyed by channel_type.
        # @return [Hash{String => Class}]
        def adapters
          BaseAdapter.registered_subclasses.index_by(&:channel_type)
        end

        # Automatically registers subclasses (same pattern as BaseAgent).
        # @param subclass [Class] The inheriting adapter class
        # @return [void]
        def inherited(subclass)
          super
          BaseAdapter.registered_subclasses << subclass
        end

        # Adapter identifier matching the channel_type column of bindings,
        # channel conversations and adapter settings.
        # @return [String]
        def channel_type
          raise NotImplementedError, "#{name} must implement .channel_type"
        end

        # Setting columns that must be present for the integration to run.
        # @return [Array<Symbol>]
        def required_setting_fields
          []
        end
      end

      # The gateway this adapter dispatches messages through. Set by the
      # gateway when it starts the adapter; nil when the adapter runs
      # standalone (e.g. in tests).
      # @return [Gateway, nil]
      attr_accessor :dispatcher

      # The tool-independent message handler bound to this adapter.
      # @return [MessageHandler]
      def handler
        @handler ||= MessageHandler.new(self)
      end

      # Hands a normalized message over for processing. When attached to a
      # gateway the message is queued for the single worker thread; otherwise
      # it is handled inline.
      # @param message [IncomingMessage] the normalized message
      # @return [void]
      def dispatch(message)
        if dispatcher
          dispatcher.enqueue(self, message)
        else
          handler.handle(message)
        end
      end

      # The settings row for this adapter.
      # @return [AiHelperChatAdapterSetting]
      def settings
        AiHelperChatAdapterSetting.for_channel(channel_type)
      end

      # Whether the integration is enabled and all required setting fields
      # are present.
      # @return [Boolean]
      def enabled?
        setting = settings
        return false unless setting.enabled

        self.class.required_setting_fields.all? { |field| setting.send(field).present? }
      end

      # Instance-level logger access for adapters.
      # @return [RedmineAiHelper::CustomLogger]
      delegate :ai_helper_logger, to: :class

      # Adapter identifier (delegates to the class-level declaration).
      # @return [String]
      delegate :channel_type, to: :class

      # Connects to the external tool and blocks while receiving events.
      # @return [void]
      def start
        raise NotImplementedError, "#{self.class.name} must implement #start"
      end

      # Closes the connection and lets #start return.
      # @return [void]
      def stop
        raise NotImplementedError, "#{self.class.name} must implement #stop"
      end

      # Posts a reply into the given thread.
      # @param channel_id [String] Channel identifier
      # @param thread_key [String] Thread identifier
      # @param text [String] Reply body
      # @return [void]
      def send_message(channel_id:, thread_key:, text:)
        raise NotImplementedError, "#{self.class.name} must implement #send_message"
      end

      # Resolves the email address of an external user.
      # @param external_user_id [String] Tool-specific user identifier
      # @return [String, nil] The email address, or nil when unavailable
      def resolve_user_email(external_user_id:)
        raise NotImplementedError, "#{self.class.name} must implement #resolve_user_email"
      end

      # Shows a processing indicator for the given message.
      # @param message [IncomingMessage] The message being processed
      # @return [void]
      def notify_processing(message:)
        raise NotImplementedError, "#{self.class.name} must implement #notify_processing"
      end

      # Whether the given error is a fatal configuration/credential error
      # that the supervisor (systemd) must not retry. Defaults to false;
      # adapters override to classify their own credential errors so ADR-006
      # ("credential problems are never retried") holds at the process level.
      # @param _error [Exception] the error raised by the adapter
      # @return [Boolean]
      def fatal_config_error?(_error)
        false
      end
    end
  end
end
