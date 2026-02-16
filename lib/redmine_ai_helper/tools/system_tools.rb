# frozen_string_literal: true
require "redmine_ai_helper/base_tools"

module RedmineAiHelper
  module Tools
    # SystemTools is a specialized tool provider for handling system-related queries in Redmine.
    class SystemTools < RedmineAiHelper::BaseTools
      define_function :list_plugins, description: "Returns a list of all plugins installed in Redmine." do
        property :dummy, type: "string", description: "Dummy property. No need to specify.", required: false
      end

      define_function :get_system_info, description: "Returns comprehensive system information including Redmine version, Ruby, Database, environment details, SCM information, and plugins. Only accessible to administrators." do
        property :dummy, type: "string", description: "Dummy property. No need to specify.", required: false
      end

      # Returns a list of all plugins installed in Redmine.
      # A dummy property is defined because at least one property is required in the tool
      # definition.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Array<Hash>] An array of hashes containing plugin information.
      def list_plugins(dummy: nil)
        plugins = Redmine::Plugin.all
        plugin_list = []
        plugins.map do |plugin|
          plugin_list <<
          {
            name: plugin.name,
            version: plugin.version,
            author: plugin.author,
            url: plugin.url,
            author_url: plugin.author_url,
          }
        end
        json = { plugins: plugin_list }
        return json
      end

      # Returns comprehensive system information.
      # Only accessible to administrators.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Hash] A hash containing detailed system information.
      def get_system_info(dummy: nil)
        unless User.current.admin?
          raise "Permission denied. Only administrators can access system information."
        end

        system_info = {}

        # Redmine version and environment
        system_info[:redmine] = {
          version: Redmine::VERSION::STRING,
          environment: Rails.env,
        }

        # Ruby information
        system_info[:ruby] = {
          version: RUBY_VERSION,
          patchlevel: RUBY_PATCHLEVEL,
          release_date: RUBY_RELEASE_DATE,
          platform: RUBY_PLATFORM,
        }

        # Rails version
        system_info[:rails] = {
          version: Rails::VERSION::STRING,
        }

        # Database information
        begin
          system_info[:database] = {
            adapter: ActiveRecord::Base.connection.adapter_name,
          }
        rescue => e
          system_info[:database] = {
            adapter: "Unknown",
            error: e.message,
          }
        end

        # Mailer configuration
        system_info[:mailer] = {
          queue: defined?(ActiveJob) ? "ActiveJob::#{Rails.application.config.active_job.queue_adapter}" : "Unknown",
          delivery: ActionMailer::Base.delivery_method.to_s,
        }

        # Redmine theme
        system_info[:redmine_settings] = {
          theme: Setting.ui_theme.present? ? Setting.ui_theme : "Default",
        }

        # SCM information (only available SCMs)
        system_info[:scm] = {}
        Redmine::Scm::Base.all.each do |scm_name|
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

        return system_info
      end
    end
  end
end
