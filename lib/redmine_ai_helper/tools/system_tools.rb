# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/log_file_locator"
require "redmine_ai_helper/util/log_file_reader"

module RedmineAiHelper
  module Tools
    # SystemTools is a specialized tool provider for handling system-related queries in Redmine.
    class SystemTools < RedmineAiHelper::BaseTools
      requires admin: true

      # Log types accepted by the log functions, shown to the LLM as an enum.
      LOG_TYPE_ENUM = RedmineAiHelper::Util::LogFileLocator::LOG_TYPES

      define_function :list_plugins, description: "Returns a list of all plugins installed in Redmine." do
        property :dummy, type: "string", description: "Dummy property. No need to specify.", required: false
      end

      define_function :get_system_info, description: "Returns comprehensive system information including Redmine version, Ruby, Database, environment details, SCM information, and plugins. Only accessible to administrators." do
        property :dummy, type: "string", description: "Dummy property. No need to specify.", required: false
      end

      define_function :get_log_file_info, description: "Returns the log files that AI Helper can read — the Redmine application log and the AI Helper plugin log — with file name, size and last modified time, or the reason a log is unavailable. Administrators only; requires log file access to be enabled in the AI Helper settings." do
        property :dummy, type: "string", description: "Dummy property. No need to specify.", required: false
      end

      define_function :read_log_tail, description: "Reads the last lines of a log file, reading at most the last 16MB (byte_limit_reached is true when that limit cut the result short). Use log_type 'redmine' (default) for Redmine errors and 'ai_helper' for problems in AI Helper itself. Start with the default line count and increase only if needed. Administrators only; requires log file access to be enabled." do
        property :log_type, type: "string", enum: LOG_TYPE_ENUM, description: "The log to read: 'redmine' (default) or 'ai_helper'.", required: false
        property :lines, type: "integer", description: "Number of lines to read from the end, 1 or more. Default 100; larger values than 1000 are capped at 1000 and lines_capped is set.", required: false
      end

      define_function :search_log, description: "Searches a log file for lines containing a keyword (plain text, not a regular expression). The file is scanned backwards from its end, at most the last 500MB. If more than max_matches lines match, only the newest max_matches are returned and truncated is true. Results are listed oldest first, with optional surrounding context. Start with the defaults (50 matches, no context) and widen only if needed. Administrators only; requires log file access to be enabled." do
        property :keyword, type: "string", description: "Text to search for. Regular expression characters have no special meaning; leading and trailing whitespace is ignored.", required: true
        property :log_type, type: "string", enum: LOG_TYPE_ENUM, description: "The log to search: 'redmine' (default) or 'ai_helper'.", required: false
        property :case_sensitive, type: "boolean", description: "Whether letter case must match. Default false.", required: false
        property :context_lines, type: "integer", description: "Number of lines to include before and after each match, 0 or more. Default 0; larger values than 10 are capped at 10 and context_lines_capped is set.", required: false
        property :max_matches, type: "integer", description: "Maximum number of matches to return, 1 or more. Default 50; larger values than 200 are capped at 200 and max_matches_capped is set.", required: false
      end

      # Returns a list of all plugins installed in Redmine.
      # A dummy property is defined because at least one property is required in the tool
      # definition.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Array<Hash>] An array of hashes containing plugin information.
      def list_plugins(dummy: nil) # rubocop:disable Lint/UnusedMethodArgument
        plugins = Redmine::Plugin.all
        plugin_list = []
        plugins.map do |plugin|
          plugin_list <<
          {
            name: plugin.name,
            version: plugin.version,
            author: plugin.author,
            url: plugin.url,
            author_url: plugin.author_url
          }
        end
        json = { plugins: plugin_list }
        json
      end

      # Returns comprehensive system information.
      # Only accessible to administrators.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Hash] A hash containing detailed system information.
      def get_system_info(dummy: nil) # rubocop:disable Lint/UnusedMethodArgument
        unless User.current.admin?
          raise "Permission denied. Only administrators can access system information."
        end

        system_info = {}

        # Redmine version and environment
        system_info[:redmine] = {
          version: Redmine::VERSION::STRING,
          environment: Rails.env
        }

        # Ruby information
        system_info[:ruby] = {
          version: RUBY_VERSION,
          patchlevel: RUBY_PATCHLEVEL,
          release_date: RUBY_RELEASE_DATE,
          platform: RUBY_PLATFORM
        }

        # Rails version
        system_info[:rails] = {
          version: Rails::VERSION::STRING
        }

        # Database information
        begin
          system_info[:database] = {
            adapter: ActiveRecord::Base.connection.adapter_name
          }
        rescue => e
          system_info[:database] = {
            adapter: "Unknown",
            error: e.message
          }
        end

        # Mailer configuration
        system_info[:mailer] = {
          queue: defined?(ActiveJob) ? "ActiveJob::#{Rails.application.config.active_job.queue_adapter}" : "Unknown",
          delivery: ActionMailer::Base.delivery_method.to_s
        }

        # Redmine theme
        system_info[:redmine_settings] = {
          theme: (Setting.ui_theme.presence || "Default")
        }

        # SCM information (only available SCMs)
        system_info[:scm] = {}
        Redmine::Scm::Base.all.each do |scm_name| # rubocop:disable Rails/FindEach
          begin
            scm_class = "Repository::#{scm_name}".constantize
            # Check if SCM is available before getting version
            if scm_class.scm_available
              version = scm_class.scm_version_string
              system_info[:scm][scm_name.downcase] = version || "Unknown"
            end
          rescue => e
            # Only include error if SCM was expected to be available
            system_info[:scm][scm_name.downcase] = "Error: #{e.message}"
          end
        end

        # Plugin information
        plugins = Redmine::Plugin.all
        system_info[:plugins] = {}
        plugins.each do |plugin|
          system_info[:plugins][plugin.id.to_s] = plugin.version.to_s
        end

        system_info
      end

      # Describes the Redmine log and the AI Helper log, in this order. A log that
      # cannot be read is reported with the reason instead of raising, so the other
      # log is still described.
      # Only accessible to administrators when log file access is enabled.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Hash] { log_files: [...] } where each entry has log_type and
      #   available, plus file_name, size_bytes and updated_at, or reason
      def get_log_file_info(dummy: nil) # rubocop:disable Lint/UnusedMethodArgument
        ensure_log_access!
        log_files = RedmineAiHelper::Util::LogFileLocator::LOG_TYPES.map { |log_type| log_file_info(log_type) }
        { log_files: log_files }
      end

      # Reads the last lines of the Redmine log or the AI Helper log.
      # Only accessible to administrators when log file access is enabled.
      # @param log_type [String, nil] "redmine" (default) or "ai_helper"
      # @param lines [Integer, nil] Number of lines (default 100, capped at 1000)
      # @return [Hash] The tail result (see LogFileReader#tail) with log_type,
      #   requested_lines and lines_capped
      def read_log_tail(log_type: nil, lines: nil)
        ensure_log_access!
        log_type = validate_log_type(log_type)
        requested_lines = lines.nil? ? RedmineAiHelper::Util::LogFileReader::DEFAULT_TAIL_LINES : lines
        count, capped = validate_integer(:lines, lines,
                                         default: RedmineAiHelper::Util::LogFileReader::DEFAULT_TAIL_LINES,
                                         min: 1, max: RedmineAiHelper::Util::LogFileReader::MAX_TAIL_LINES)
        path = resolve_log_path(log_type)
        result = read_log(log_type, path) { |reader| reader.tail(lines: count) }
        { log_type: log_type, requested_lines: requested_lines, lines_capped: capped }.merge(result)
      end

      # Searches the Redmine log or the AI Helper log for a keyword.
      # Only accessible to administrators when log file access is enabled.
      # @param keyword [String] Text to search for, matched literally
      # @param log_type [String, nil] "redmine" (default) or "ai_helper"
      # @param case_sensitive [Boolean, nil] Whether letter case must match (default false)
      # @param context_lines [Integer, nil] Lines before and after each match (default 0, capped at 10)
      # @param max_matches [Integer, nil] Matches to return (default 50, capped at 200)
      # @return [Hash] The search result (see LogFileReader#search) with log_type,
      #   context_lines_capped and max_matches_capped
      def search_log(keyword:, log_type: nil, case_sensitive: nil, context_lines: nil, max_matches: nil)
        ensure_log_access!
        log_type = validate_log_type(log_type)
        keyword = keyword.to_s.strip
        raise "Invalid argument: keyword must not be empty" if keyword.empty?

        case_sensitive = false if case_sensitive.nil?
        raise "Invalid argument: case_sensitive must be true or false" unless [ true, false ].include?(case_sensitive)

        context, context_capped = validate_integer(:context_lines, context_lines, default: 0, min: 0,
                                                   max: RedmineAiHelper::Util::LogFileReader::MAX_CONTEXT_LINES)
        limit, limit_capped = validate_integer(:max_matches, max_matches,
                                               default: RedmineAiHelper::Util::LogFileReader::DEFAULT_MAX_MATCHES,
                                               min: 1, max: RedmineAiHelper::Util::LogFileReader::MAX_MATCHES_LIMIT)
        path = resolve_log_path(log_type)
        result = read_log(log_type, path) do |reader|
          reader.search(keyword: keyword, case_sensitive: case_sensitive, context_lines: context, max_matches: limit)
        end
        { log_type: log_type }.merge(result).merge(context_lines_capped: context_capped, max_matches_capped: limit_capped)
      end

      private

      # Rejects the call before any file is touched unless the current user is an
      # administrator and log file access is enabled. The administrator check
      # comes first, so non-administrators learn nothing about the setting.
      # The setting and tab names are given in the current locale, as shown on
      # the settings page.
      # @raise [RuntimeError] If the user is not an administrator or access is disabled
      def ensure_log_access!
        raise "Permission denied. Only administrators can access log files." unless User.current.admin?
        return if AiHelperSetting.log_access_enabled?

        setting = ::I18n.t("activerecord.attributes.ai_helper_setting.log_access_enabled")
        tab = ::I18n.t("ai_helper.settings.tab_general")
        raise "Log file access is disabled. An administrator can enable it with \"#{setting}\" on the \"#{tab}\" tab of the AI Helper settings page."
      end

      # @param log_type [String, nil] The log type given by the caller
      # @return [String] The log type, defaulting to "redmine"
      # @raise [RuntimeError] If the log type is not supported (the value is not echoed)
      def validate_log_type(log_type)
        return RedmineAiHelper::Util::LogFileLocator::DEFAULT_LOG_TYPE if log_type.nil?
        return log_type if RedmineAiHelper::Util::LogFileLocator::LOG_TYPES.include?(log_type)

        raise "Invalid argument: log_type must be one of #{RedmineAiHelper::Util::LogFileLocator::LOG_TYPES.join(", ")}"
      end

      # Validates an integer argument and caps it at the maximum.
      # @param name [Symbol] Argument name used in the error message
      # @param value [Integer, nil] The value given by the caller
      # @param default [Integer] Value used when the argument is omitted
      # @param min [Integer] Smallest accepted value
      # @param max [Integer] Largest value; larger values are capped
      # @return [Array(Integer, Boolean)] The value to use and whether it was capped
      # @raise [RuntimeError] If the value is not an integer of min or more
      def validate_integer(name, value, default:, min:, max:)
        return [ default, false ] if value.nil?
        unless value.is_a?(Integer) && value >= min
          raise "Invalid argument: #{name} must be an integer of #{min} or more"
        end
        return [ max, true ] if value > max

        [ value, false ]
      end

      # @param log_type [String] A validated log type
      # @return [String] Path of the log file (never passed to the LLM)
      # @raise [RuntimeError] If the log is not written to a file
      def resolve_log_path(log_type)
        RedmineAiHelper::Util::LogFileLocator.resolve(log_type)
      rescue RedmineAiHelper::Util::LogFileLocator::UnavailableError => e
        raise unavailable_message(log_type, e)
      end

      # Describes one log for get_log_file_info, reporting an unreadable log with
      # the reason instead of raising.
      # @param log_type [String] One of LogFileLocator::LOG_TYPES
      # @return [Hash] log_type and available, plus the file information or reason
      def log_file_info(log_type)
        path = RedmineAiHelper::Util::LogFileLocator.resolve(log_type)
        { log_type: log_type, available: true }.merge(RedmineAiHelper::Util::LogFileReader.new(path).info)
      rescue RedmineAiHelper::Util::LogFileLocator::UnavailableError => e
        { log_type: log_type, available: false, reason: unavailable_message(log_type, e) }
      rescue RedmineAiHelper::Util::LogFileReader::FileNotReadableError => e
        { log_type: log_type, available: false, reason: file_not_readable_message(log_type, e) }
      end

      # @param log_type [String]
      # @param error [RedmineAiHelper::Util::LogFileLocator::UnavailableError]
      # @return [String] Message naming the log type and the reason
      def unavailable_message(log_type, error)
        "The #{log_type} log is not available: #{error.message}"
      end

      # Yields a reader for the log file and turns a missing or unreadable file
      # into an error message that names the log type and the file name only.
      # @param log_type [String] A validated log type
      # @param path [String] Path of the log file
      # @yieldparam reader [RedmineAiHelper::Util::LogFileReader]
      # @return [Object] The value of the block
      # @raise [RuntimeError] If the file does not exist or cannot be read
      def read_log(log_type, path)
        yield RedmineAiHelper::Util::LogFileReader.new(path)
      rescue RedmineAiHelper::Util::LogFileReader::FileNotReadableError => e
        raise file_not_readable_message(log_type, e)
      end

      # @param log_type [String]
      # @param error [RedmineAiHelper::Util::LogFileReader::FileNotReadableError]
      # @return [String] Message naming the log type and the file name only
      def file_not_readable_message(log_type, error)
        detail = error.reason == :not_found ? "does not exist" : "cannot be read"
        "The #{log_type} log file #{error.file_name} #{detail}."
      end
    end
  end
end
