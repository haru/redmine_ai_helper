# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/util/config_file"

module RedmineAiHelper
  module Util
    # Decides which file on the server holds each log that the log functions of
    # SystemTools may read. The file is derived only from the log type, never from
    # user or LLM input, so no other file can be reached (FR-006).
    #
    # The returned path is for Ruby-side use only and must not be handed to the LLM.
    # See docs/adr/039-log-file-location-resolved-from-runtime-logger.md.
    class LogFileLocator
      include RedmineAiHelper::Logger

      # Log types that can be read.
      LOG_TYPES = %w[redmine ai_helper].freeze

      # Log type used when the caller does not specify one.
      DEFAULT_LOG_TYPE = "redmine"

      # Raised when a log is not written to a file that can be read.
      # The message states the reason only and never contains a path.
      class UnavailableError < StandardError; end

      class << self
        # Returns the file currently written by the given log.
        # Whether the file exists or can be read is checked later by LogFileReader.
        # @param log_type [String] One of LOG_TYPES
        # @return [String] Absolute path of the log file (do not pass it to the LLM)
        # @raise [ArgumentError] If log_type is not one of LOG_TYPES
        # @raise [UnavailableError] If no logger writes the log to a file
        def resolve(log_type)
          raise ArgumentError, "Unknown log type" unless LOG_TYPES.include?(log_type)

          log_type == "redmine" ? resolve_redmine : resolve_ai_helper
        end

        private

        # Finds the file written by the AI Helper logger, using the same rule as
        # RedmineAiHelper::CustomLogger. A config.yml that cannot be read or
        # parsed is reported without its path; the details go to the server log.
        # @return [String] Path of the AI Helper log
        def resolve_ai_helper
          path = ai_helper_log_path
          raise UnavailableError, "AI Helper writes its log into the Redmine application log because config/ai_helper/config.yml has no logger section." unless path

          reject_non_regular_file(path.to_s, "AI Helper")
        end

        # @return [Pathname, nil] The AI Helper log file, or nil without a logger section
        # @raise [UnavailableError] If config.yml cannot be read or its logger section is invalid
        def ai_helper_log_path
          config = RedmineAiHelper::Util::ConfigFile.load_config
          raise TypeError, "config.yml is not a mapping" unless config.is_a?(Hash)
          raise TypeError, "logger section is not a mapping" unless config[:logger].nil? || config[:logger].is_a?(Hash)

          RedmineAiHelper::CustomLogger.log_file_path(config)
        rescue Psych::Exception, SystemCallError, NoMethodError, TypeError => e
          ai_helper_logger.warn("[#{name}] cannot read the AI Helper log location from config.yml: #{e.class}: #{e.message}")
          raise UnavailableError, "config/ai_helper/config.yml could not be read, or its logger section is invalid."
        end

        # Finds the file written by the running Rails.logger, looking through the
        # broadcasts of an ActiveSupport::BroadcastLogger.
        # @return [String] Path of the Redmine application log
        def resolve_redmine
          path = candidate_loggers(Rails.logger).filter_map { |logger| file_path_of(logger) }.first
          return reject_non_regular_file(path, "Redmine") if path

          raise UnavailableError, redmine_unavailable_reason
        end

        # A logger can be given a device or a pipe such as /dev/stdout, which is
        # not a log file that can be read back. A path that does not exist is
        # left to LogFileReader, which reports the missing file.
        # @param path [String] Path of the log file
        # @param owner [String] Name of the application writing the log
        # @return [String] The path
        # @raise [UnavailableError] If the path exists but is not a regular file
        def reject_non_regular_file(path, owner)
          return path if !File.exist?(path) || File.file?(path)

          raise UnavailableError, "#{owner} writes its log to a device or a pipe, not to a regular file."
        end

        # @param logger [::Logger, ActiveSupport::BroadcastLogger]
        # @return [Array<::Logger>] The loggers that actually write the log
        def candidate_loggers(logger)
          return logger.broadcasts if logger.is_a?(ActiveSupport::BroadcastLogger)

          [ logger ]
        end

        # LogDevice#filename is set when the logger was given a path or a File
        # object, and nil for IO streams such as $stdout, $stderr and StringIO.
        # A path that is not a regular file (e.g. /dev/stdout) is rejected by
        # reject_non_regular_file.
        # @param logger [::Logger]
        # @return [String, nil] The file the logger writes to, or nil when it does
        #   not write to a file
        def file_path_of(logger)
          logdev = logger.instance_variable_get(:@logdev)
          return nil unless logdev.respond_to?(:filename) && logdev.filename

          logdev.filename.to_s
        end

        # @return [String] Why the Redmine application log cannot be read
        def redmine_unavailable_reason
          if ENV["RAILS_LOG_TO_STDOUT"].present?
            "Redmine writes its log to standard output because RAILS_LOG_TO_STDOUT is set."
          else
            "The Redmine logger does not write to a file; it may write to syslog or standard error."
          end
        end
      end
    end
  end
end
