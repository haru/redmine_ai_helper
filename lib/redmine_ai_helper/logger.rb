# frozen_string_literal: true
module RedmineAiHelper
  # Logger mixin for AI Helper plugin
  module Logger
    # Hook to extend including class with ClassMethods
    # @param base [Class] The class including this module
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Class methods for logging
    module ClassMethods
      # Get the AI Helper logger instance
      # @return [CustomLogger] The logger instance
      def ai_helper_logger
        @ai_helper_logger ||= begin
            RedmineAiHelper::CustomLogger.instance
          end
      end

      # Log debug message
      # @param message [String] The message to log
      def debug(message)
        ai_helper_logger.debug("[#{self.name}] #{message}")
      end

      # Log info message
      # @param message [String] The message to log
      def info(message)
        ai_helper_logger.info("[#{self.name}] #{message}")
      end

      # Log warning message
      # @param message [String] The message to log
      def warn(message)
        ai_helper_logger.warn("[#{self.name}] #{message}")
      end

      # Log error message
      # @param message [String] The message to log
      def error(message)
        ai_helper_logger.error("[#{self.name}] #{message}")
      end
    end

    # Get the AI Helper logger instance
    # @return [CustomLogger] The logger instance
    def ai_helper_logger
      self.class.ai_helper_logger
    end

    # Log debug message
    # @param message [String] The message to log
    def debug(message)
      ai_helper_logger.debug("[#{self.class.name}] #{message}")
    end

    # Log info message
    # @param message [String] The message to log
    def info(message)
      ai_helper_logger.info("[#{self.class.name}] #{message}")
    end

    # Log warning message
    # @param message [String] The message to log
    def warn(message)
      ai_helper_logger.warn("[#{self.class.name}] #{message}")
    end

    # Log error message
    # @param message [String] The message to log
    def error(message)
      ai_helper_logger.error("[#{self.class.name}] #{message}")
    end
  end

  # Custom logger implementation for AI Helper
  class CustomLogger
    include Singleton

    def initialize
      log_file_path = Rails.root.join("log", "ai_helper.log")

      config = RedmineAiHelper::Util::ConfigFile.load_config

      logger = config[:logger]
      unless logger
        @logger = Rails.logger
        return
      end
      log_level = "info"
      log_level = logger[:level] if logger[:level]
      log_file_path = Rails.root.join("log", logger[:file]) if logger[:file]
      @logger = ::Logger.new(log_file_path, "daily")
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity} -- #{msg}\n"
      end
      set_log_level(log_level)
    end

    # Log debug message
    # @param message [String] The message to log
    def debug(message)
      @logger.debug(message)
    end

    # Log info message
    # @param message [String] The message to log
    def info(message)
      @logger.info(message)
    end

    # Log warning message
    # @param message [String] The message to log
    def warn(message)
      @logger.warn(message)
    end

    # Log error message
    # @param message [String] The message to log
    def error(message)
      @logger.error(message)
    end

    # Set the log level
    # @param log_level [String, Integer] The log level
    def set_log_level(log_level)
      level = case log_level.to_s
        when "debug"
          ::Logger::DEBUG
        when "info"
          ::Logger::INFO
        when "warn"
          ::Logger::WARN
        when "error"
          ::Logger::ERROR
        else
          ::Logger::INFO
        end
      @logger.level = level
    end
  end
end
