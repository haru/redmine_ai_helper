# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/project_metrics_calculator"

module RedmineAiHelper
  module Tools
    # ProjectTools is a specialized tool for handling Redmine project-related queries.
    class ProjectTools < RedmineAiHelper::BaseTools
      define_function :list_projects, description: "List all projects visible to the current user. It returns the project ID, name, identifier, description, created_on, and last_activity_date." do
        property :dummy, type: "string", description: "dummy property", required: false
      end

      # List all projects visible to the current user.
      # A dummy property is defined because at least one property is required in the tool
      # definition.
      # @param dummy [String] Dummy property to satisfy the tool definition requirement.
      # @return [Array<Hash>] An array of hashes containing project information.
      def list_projects(dummy: nil) # rubocop:disable Lint/UnusedMethodArgument
        list = accessible_projects.map do |project|
          {
            id: project.id,
            name: project.name,
            identifier: project.identifier,
            description: project.description,
            created_on: project.created_on,
            last_activity_date: project.last_activity_date
          }
        end
        list
      end

      define_function :read_project, description: "Read a project from the database and return it as a JSON object. It returns the project ID, name, identifier, description, homepage, status, is_public, inherit_members, created_on, updated_on, subprojects, custom_fields, and last_activity_date." do
        property :project_id, type: "integer", description: "The project ID of the project to return.", required: false
        property :project_name, type: "string", description: "The project name of the project to return.", required: false
        property :project_identifier, type: "string", description: "The project identifier of the project to return.", required: false
      end

      # Read a project from the database.
      # @param project_id [Integer] The project ID of the project to return.
      # @param project_name [String] The project name of the project to return.
      # @param project_identifier [String] The project identifier of the project to return.
      # @return [Hash] A hash containing project information.
      def read_project(project_id: nil, project_name: nil, project_identifier: nil)
        if project_id
          project = Project.find_by(id: project_id)
        elsif project_name
          project = Project.find_by(name: project_name)
        elsif project_identifier
          project = Project.find_by(identifier: project_identifier)
        else
          raise "No id or name or Identifier specified."
        end

        raise "Project not found" unless project
        raise "You don't have permission to view this project" unless accessible_project? project
        project_json = {
          id: project.id,
          name: project.name,
          identifier: project.identifier,
          description: project.description,
          homepage: project.homepage,
          status: project.status,
          is_public: project.is_public,
          inherit_members: project.inherit_members,
          created_on: project.created_on,
          updated_on: project.updated_on,
          subprojects: project.children.select { |p| accessible_project? p }.map do |child|
            {
              id: child.id,
              name: child.name,
              identifier: child.identifier,
              description: child.description
            }
          end,
          custom_fields: format_project_custom_fields(project),
          last_activity_date: project.last_activity_date
        }
        project_json
      end

      define_function :project_members, description: "List all members of the projects. It can be used to obtain the ID from the user's name. It can also be used to obtain the roles that the user has in the projects. Member information includes user_id, login, user_name, and roles." do
        property :project_ids, type: "array", description: "The project IDs of the projects to return.", required: true do
          item type: "integer"
        end
      end

      # List all members of the project.
      # @param project_ids [Array<Integer>] The project IDs of the projects to return.
      # @return [Array<Hash>] An array of hashes containing member information.
      def project_members(project_ids:)
        projects = Project.where(id: project_ids)
        return ToolResponse.create_error "No projects found" if projects.empty?

        list = projects.filter { |p| accessible_project? p }.map do |project|
          return ToolResponse.create_error "You don't have permission to view this project" unless accessible_project? project

          members = project.members.map do |member|
            {
              user_id: member.user_id,
              login: member.user.login,
              user_name: member.user.name,
              roles: member.roles.map do |role|
                {
                  id: role.id,
                  name: role.name
                }
              end
            }
          end
          {
            project_id: project.id,
            project_name: project.name,
            members: members
          }
        end
        { projects: list }
      end

      define_function :project_enabled_modules, description: "List all enabled modules of the projects. It shows the functions and plugins enabled in this projects." do
        property :project_id, type: "integer", description: "The project ID of the project to return.", required: true
      end

      # List all modules of the project.
      # It shows the functions and plugins enabled in this project.
      # @param project_id [Integer] The project ID of the project to return.
      # @return [Array<Hash>] An array of hashes containing module information.
      def project_enabled_modules(project_id:)
        project = Project.find(project_id)
        return ToolResponse.create_error "Project not found" unless project
        return ToolResponse.create_error "You don't have permission to view this project" unless accessible_project? project

        enabled_modules = project.enabled_modules.map do |enabled_module|
          {
            name: enabled_module.name
          }
        end
        json = {
          project_id: project_id,
          enabled_modules: enabled_modules
        }
        json
      end

      define_function :list_project_activities, description: "List all activities of the project. It returns the activity ID, event_datetime, event_type, event_title, event_description, event_url, user_id (the ID of the user who performed the activity, or null if unknown), project ({id, name}), and hours (numeric, only for time_entries activities). Use event_types to filter by event type (e.g. [\"issues\", \"time_entries\"]); multiple types are combined with OR. Omit project_id to list activities across all projects that have the AI Helper module enabled and are accessible to the current user." do
        property :project_id, type: "integer", description: "The project ID of the activities to return. Omit this to list activities across all projects that have the AI Helper module enabled and are accessible to the current user.", required: false
        property :author_id, type: "integer", description: "The user ID of the author of the activity. If not specified, it will return all activities.", required: false
        property :limit, type: "integer", description: "The maximum number of activities to return. Defaults to 100 when not specified.", required: false
        property :start_date, type: "string", description: "The start date of the activities to return.", required: false
        property :end_date, type: "string", description: "The end date of the activities to return. If not specified, it will return all activities.", required: false
        property :event_types, type: "array", description: "Filter activities by event type. Multiple types are combined with OR. Omit to return all types. Valid values: issues, changesets, news, documents, files, wiki_edits, messages, time_entries.", required: false do
          item type: "string", description: "An event type to filter by."
        end
      end

      # List all activities of the project. When project_id is omitted, activities are aggregated
      # across all projects that have the AI Helper module enabled and are accessible to the current
      # user (see #accessible_project?).
      # @param project_id [Integer, nil] The project ID of the activities to return. Omit to list activities across all accessible AI-Helper-enabled projects.
      # @param author_id [Integer] The user ID of the author of the activity. If not specified, it will return all activities.
      # @param limit [Integer] The maximum number of activities to return. Defaults to 100 when not specified.
      # @param start_date [DateTime] The start date of the activities to return.
      # @param end_date [DateTime] The end date of the activities to return. If not specified, it will return all activities.
      # @param event_types [Array<String>, nil] Filter by event type. Multiple types are OR-combined. Omit for all types.
      #   An error is returned if any value is not a valid event type (see Redmine::Activity.available_event_types).
      # @return [RedmineAiHelper::ToolResponse] A ToolResponse whose value contains :activities, an array of hashes
      #   each with id, event_datetime, event_type, event_title, event_description, event_url, user_id (the ID
      #   of the user who performed the activity, or nil if it cannot be determined), project ({id, name}),
      #   and hours (numeric, only for time_entries activities).
      def list_project_activities(project_id: nil, author_id: nil, limit: nil, start_date: nil, end_date: nil, event_types: nil)
        if project_id
          project = Project.find_by(id: project_id)
          return ToolResponse.create_error "Project not found" unless project
          return ToolResponse.create_error "You don't have permission to view this project" unless accessible_project? project
        end

        author = author_id ? User.find(author_id) : nil
        limit ||= 100
        start_date ||= 30.days.ago
        end_date ||= 1.day.from_now

        current_user = User.current
        fetcher = Redmine::Activity::Fetcher.new(current_user, project: project, author: author)
        if event_types.present?
          unknown_event_types = event_types - Redmine::Activity.available_event_types
          if unknown_event_types.any?
            return ToolResponse.create_error "Unknown event_types: #{unknown_event_types.join(', ')}. Valid values: #{Redmine::Activity.available_event_types.join(', ')}."
          end
          fetcher.scope = event_types
        end
        ai_helper_logger.debug "current_user: #{current_user}, project: #{project}, author: #{author}, start_date: #{start_date}, end_date: #{end_date}, limit: #{limit}, event_types: #{event_types}"
        events = fetcher.events(start_date, end_date)

        unless project
          accessible_project_ids = accessible_projects.map(&:id).to_set
          events = events.select { |event| accessible_project_ids.include?(event_project_id(event)) }
        end

        events = events.sort_by(&:event_datetime).reverse.first(limit)

        project_ids = events.map { |event| event_project_id(event) }.compact.uniq
        projects_by_id = Project.where(id: project_ids).index_by(&:id)

        list = []
        events.each do |event|
          list << {
            id: event.id,
            event_datetime: event.event_datetime,
            event_type: event.event_type,
            event_title: event.event_title,
            event_description: event.event_description,
            event_url: event.event_url,
            user_id: event.event_author.is_a?(User) ? event.event_author.id : nil,
            project: format_named_record(projects_by_id[event_project_id(event)]),
            hours: event.is_a?(TimeEntry) ? event.hours : nil
          }
        end
        json = { activities: list }
        ToolResponse.create_success json # TODO: Should just return json?
      end

      # Project ID of an activity event, without loading the project association when the
      # event itself already carries the foreign key.
      # @param event [Object] An activity event returned by Redmine::Activity::Fetcher.
      # @return [Integer, nil] The project ID, or nil if it cannot be determined.
      def event_project_id(event)
        event.respond_to?(:project_id) ? event.project_id : event.project&.id
      end

      define_function :get_metrics, description: "REQUIRED FIRST STEP: Get comprehensive project health metrics for a specific project. You MUST call this function BEFORE generating any project health report. Returns essential raw data including issue statistics, timing metrics, workload distribution, quality metrics, progress metrics, and team metrics that are absolutely necessary for accurate health analysis." do
        property :project_id, type: "integer", description: "The project ID to get health metrics for.", required: true
        property :version_id, type: "integer", description: "The version ID to filter metrics by. If not specified, returns metrics for all versions.", required: false
        property :start_date, type: "string", description: "Start date for metrics collection in YYYY-MM-DD format. If not specified, uses 30 days ago.", required: false
        property :end_date, type: "string", description: "End date for metrics collection in YYYY-MM-DD format. If not specified, uses today.", required: false
      end

      # Retrieve comprehensive project health metrics for a specific project.
      # This method aggregates various statistics including issue counts, timing,
      # workload distribution, quality indicators, progress tracking, and team metrics.
      # Should be called before generating any project health report.
      # @param project_id [Integer] The project ID to get health metrics for.
      # @param version_id [Integer, nil] The version ID to filter metrics by.
      # @param start_date [String, nil] Start date in YYYY-MM-DD format (defaults to 30 days ago).
      # @param end_date [String, nil] End date in YYYY-MM-DD format (defaults to today).
      # @return [Hash] A hash containing comprehensive project metrics including issue statistics,
      #   timing metrics, workload metrics, quality metrics, progress metrics, member metrics,
      #   update frequency metrics, estimation accuracy metrics, attachment metrics, and issue list.
      def get_metrics(project_id:, version_id: nil, start_date: nil, end_date: nil)
        ai_helper_logger.info "get_metrics called with args: project_id=#{project_id}, version_id=#{version_id}, start_date=#{start_date}, end_date=#{end_date}"

        begin
          project = Project.find(project_id)
          raise "Project not found" unless project
          raise "You don't have permission to view this project" unless accessible_project? project

          start_date_obj = start_date ? Date.parse(start_date) : nil
          end_date_obj = end_date ? Date.parse(end_date) : nil

          if start_date_obj || end_date_obj
            start_date_obj ||= 30.days.ago.to_date
            end_date_obj ||= Date.current
            issues_scope = project.issues.where(created_on: start_date_obj.beginning_of_day..end_date_obj.end_of_day)
          else
            start_date_obj = nil
            end_date_obj = nil
            issues_scope = project.issues
          end
          issues_scope = issues_scope.where(fixed_version_id: version_id) if version_id

          # Limit the number of issues to prevent memory issues and long processing times
          # For health reports, we typically don't need more than 10,000 issues for meaningful analysis
          issues = issues_scope.includes(:status, :priority, :tracker, :assigned_to, :author, :fixed_version, :time_entries, :journals, :attachments).limit(10000)

          metrics_calculator = RedmineAiHelper::ProjectMetricsCalculator.new
          repository_metrics = if version_id
            {}
          else
            metrics_calculator.calculate_repository_metrics(project, start_date: start_date_obj, end_date: end_date_obj)
          end

          metrics = {
            project_info: {
              id: project.id,
              name: project.name,
              identifier: project.identifier,
              created_on: project.created_on,
              last_activity_date: project.last_activity_date
            },
            period: {
              start_date: start_date_obj,
              end_date: end_date_obj,
              version_id: version_id
            },
            issue_statistics: metrics_calculator.calculate_issue_statistics(issues),
            timing_metrics: metrics_calculator.calculate_timing_metrics(issues),
            workload_metrics: metrics_calculator.calculate_workload_metrics(issues),
            quality_metrics: metrics_calculator.calculate_quality_metrics(issues),
            progress_metrics: metrics_calculator.calculate_progress_metrics(issues),
            member_metrics: metrics_calculator.calculate_member_metrics(issues),
            update_frequency_metrics: metrics_calculator.calculate_update_frequency_metrics(issues),
            estimation_accuracy_metrics: metrics_calculator.calculate_estimation_accuracy_metrics(issues),
            attachment_metrics: metrics_calculator.calculate_attachment_metrics(issues),
            repository_metrics: repository_metrics
          }

          ai_helper_logger.info "get_metrics returning: #{metrics.to_json}"
          # ToolResponse.create_success metrics
          metrics
        rescue => e
          ai_helper_logger.error "get_metrics error: #{e.message}"
          ai_helper_logger.error e.backtrace.join("\n")
          raise e
        end
      end

      private

      def format_project_custom_fields(project)
        project.custom_field_values.map do |cfv|
          { id: cfv.custom_field.id, name: cfv.custom_field.name, value: cfv.value }
        end
      end
    end
  end
end
