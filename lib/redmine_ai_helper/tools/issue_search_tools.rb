# frozen_string_literal: true

module RedmineAiHelper
  module Tools
    # A class that provides functionality to the Agent for retrieving issue information
    class IssueSearchTools < RedmineAiHelper::BaseTools
      # Sort fields supported by search_issues. Only attributes the Issue model holds directly;
      # related-object sorting (e.g. assignee name) is out of scope.
      SUPPORTED_SORT_FIELDS = %w[id created_on updated_on due_date start_date done_ratio].freeze

      # Shared item schema for field/operator/values-of-string search entries
      # (used by fields, date_fields, time_fields).
      STRING_VALUES_ITEM = proc do
        property :field_name, type: "string", description: "The name of the field to search.", required: true
        property :operator, type: "string", description: "The operator to use for the search.", required: true
        property :values, type: "array", description: "The values to search for.", required: true do
          item type: "string", description: "The value to search for."
        end
      end

      # Shared item schema for field/operator/values-of-integer search entries
      # (used by number_fields, status_field).
      INTEGER_VALUES_ITEM = proc do
        property :field_name, type: "string", description: "The name of the field to search.", required: true
        property :operator, type: "string", description: "The operator to use for the search.", required: true
        property :values, type: "array", description: "The values to search for.", required: true do
          item type: "integer", description: "The value to search for."
        end
      end

      define_function :search_issues, description: "Search issues based on the filter conditions and return matching issues. For search items with '_id', specify the ID instead of the name of the search target. If you do not know the ID, you need to call capable_issue_properties in advance to obtain the ID. Default limit is 50 issues. Only projects with the AI Helper module enabled can be searched. Omit project_id to search across all projects that have the AI Helper module enabled and are accessible to the current user." do
        property :project_id, type: "integer", description: "The project ID of the project to search in. Only projects with the AI Helper module enabled can be searched. Omit this to search across all projects that have the AI Helper module enabled and are accessible to the current user.", required: false
        property :limit, type: "integer", description: "Maximum number of issues to return. Default is 50.", required: false
        property :fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue.", &STRING_VALUES_ITEM
        end
        property :date_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue.", &STRING_VALUES_ITEM
        end
        property :time_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue.", &STRING_VALUES_ITEM
        end
        property :number_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue.", &INTEGER_VALUES_ITEM
        end
        property :text_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :value, type: "array", description: "The values to search for.", required: true do
              item type: "string", description: "The value to search for."
            end
          end
        end
        property :status_field, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue.", &INTEGER_VALUES_ITEM
        end
        property :custom_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_id, type: "integer", description: "The ID of the custom field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "string", description: "The value to search for."
            end
          end
        end
        property :sort, type: "object", description: "Sort order for the results. Defaults to id descending (newest first) when omitted.", required: false do
          property :field, type: "string", description: "Sort field. One of: id, created_on, updated_on, due_date, start_date, done_ratio.", required: true
          property :direction, type: "string", description: "Sort direction. asc or desc. Defaults to desc.", required: false
        end
      end
      # Search issues based on filter conditions and return matching issues
      # @param project_id [Integer, nil] The project ID of the project to search in. The project must have the ai_helper module enabled and be accessible to the current user. When omitted, searches across all projects that have the ai_helper module enabled and are accessible to the current user.
      # @param limit [Integer] Maximum number of issues to return. Default is 50.
      # @param fields [Array] Search fields for the issue.
      # @param date_fields [Array] Date search fields for the issue.
      # @param time_fields [Array] Time search fields for the issue.
      # @param number_fields [Array] Number search fields for the issue.
      # @param text_fields [Array] Text search fields for the issue.
      # @param status_field [Array] Status search fields for the issue.
      # @param custom_fields [Array] Custom field search filters.
      # @param sort [Hash] Sort order with :field (one of SUPPORTED_SORT_FIELDS) and optional :direction (asc/desc, default desc). Defaults to id descending when omitted.
      # @return [Hash] A hash containing issues array and total_count.
      # @raise [RuntimeError] if project_id is given but the project is not accessible with the ai_helper module enabled.
      # @raise [ActiveRecord::RecordNotFound] if project_id is given but no project matches it.
      def search_issues(project_id: nil, limit: 50, fields: [], date_fields: [], time_fields: [], number_fields: [], text_fields: [], status_field: [], custom_fields: [], sort: nil)
        fields = deep_symbolize_array(fields)
        date_fields = deep_symbolize_array(date_fields)
        time_fields = deep_symbolize_array(time_fields)
        number_fields = deep_symbolize_array(number_fields)
        text_fields = deep_symbolize_array(text_fields)
        status_field = deep_symbolize_array(status_field)
        custom_fields = deep_symbolize_array(custom_fields)
        sort = normalize_sort_param(deep_symbolize_hash(sort))

        limit = [ limit.to_i, 1 ].max
        project = nil
        if project_id
          project = Project.find(project_id)
          # Guard both search paths at once: projects without the ai_helper module (or
          # without access for the current user) must never expose their issues.
          raise "ai_helper is not enabled for project: id = #{project_id}" unless accessible_project?(project)
        end

        if fields.empty? && date_fields.empty? && time_fields.empty? && number_fields.empty? && text_fields.empty? && status_field.empty? && custom_fields.empty?
          # No conditions: return open visible issues for the project (same as Redmine default).
          # Without a project, scope to all projects the current user may search via AI Helper.
          scope = Issue.visible(User.current).open
          scope = project ? scope.where(project_id: project.id) : scope.joins(:project).where(Project.allowed_to_condition(User.current, :view_ai_helper))
          order = sort ? { sort[:field] => sort[:direction] } : { id: :desc }
          issues = scope.includes(:status, :priority, :tracker, :assigned_to, :author, :custom_values)
                        .order(order).limit(limit)
          total_count = scope.count
          return { issues: format_issues(issues), total_count: total_count }
        end

        validate_errors = validate_search_params(fields, date_fields)
        raise(validate_errors.join("\n")) if validate_errors.length > 0

        params = { fields: [], operators: {}, values: {} }
        if project
          params[:fields] << "project_id"
          params[:operators]["project_id"] = "="
          params[:values]["project_id"] = [ project_id.to_s ]
        end

        fields.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:values]
        end

        date_fields.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:values]
        end

        time_fields.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:values]
        end

        number_fields.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:values].map(&:to_s)
        end

        text_fields.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:value]
        end

        status_field.each do |field|
          params[:fields] << field[:field_name]
          params[:operators][field[:field_name]] = field[:operator]
          params[:values][field[:field_name]] = field[:values].map(&:to_s)
        end

        builder = IssueQueryBuilder.new(params, sort: sort)
        custom_fields.each do |field|
          builder.add_custom_field_filter(field[:field_id], field[:operator], field[:values].map(&:to_s))
        end

        issues = builder.execute(project, user: User.current, limit: limit)
        total_count = builder.count(project, user: User.current)

        { issues: format_issues(issues), total_count: total_count }
      end

      private

      # Format issues for API response
      # @param issues [Array<Issue>] Array of Issue objects
      # @return [Array<Hash>] Formatted issue hashes
      def format_issues(issues)
        issues.map do |issue|
          {
            id: issue.id,
            subject: issue.subject,
            description: issue.description,
            status: { id: issue.status.id, name: issue.status.name },
            priority: { id: issue.priority.id, name: issue.priority.name },
            tracker: { id: issue.tracker.id, name: issue.tracker.name },
            assigned_to: issue.assigned_to ? { id: issue.assigned_to.id, name: issue.assigned_to.name } : nil,
            author: { id: issue.author.id, name: issue.author.name },
            created_on: issue.created_on,
            updated_on: issue.updated_on,
            due_date: issue.due_date,
            done_ratio: issue.done_ratio,
            custom_fields: format_custom_fields(issue)
          }
        end
      end

      # Format custom field values for an issue
      # @param issue [Issue] The issue to get custom fields from
      # @return [Array<Hash>] Array of custom field hashes with id, name, and value
      def format_custom_fields(issue)
        issue.custom_field_values.map do |cfv|
          { id: cfv.custom_field.id, name: cfv.custom_field.name, value: cfv.value }
        end
      end

      # Validate and normalize the sort param for the search_issues tool
      # @param sort [Hash, nil] Raw sort param with :field (required) and :direction (optional)
      # @return [Hash, nil] Normalized { field: Symbol, direction: Symbol }, or nil if sort was nil
      def normalize_sort_param(sort)
        return nil if sort.nil?

        field = sort[:field]
        if field.nil?
          raise "sort.field is required. Supported sort fields are: #{SUPPORTED_SORT_FIELDS.join(', ')}."
        end

        field = field.to_s
        unless SUPPORTED_SORT_FIELDS.include?(field)
          raise "Unsupported sort field '#{field}'. Supported sort fields are: #{SUPPORTED_SORT_FIELDS.join(', ')}."
        end

        direction = sort[:direction].nil? ? "desc" : sort[:direction].to_s.downcase
        unless %w[asc desc].include?(direction)
          raise "Invalid sort direction '#{sort[:direction]}'. Direction must be 'asc' or 'desc'."
        end

        { field: field.to_sym, direction: direction.to_sym }
      end

      # Validate the parameters for the search_issues tool
      def validate_search_params(fields, date_fields)
        errors = []

        (fields || []).each do |field|
          unless field.is_a?(Hash)
            ai_helper_logger.warn "validate_search_params: field is not a Hash. field=#{field.inspect}"
            next
          end
          if field[:field_name].nil?
            safe_keys = field.respond_to?(:keys) ? field.keys : nil
            ai_helper_logger.warn "validate_search_params: field_name is nil. field_keys=#{safe_keys}"
            errors << "field_name is required but was not provided."
            next
          end
          if field[:values].nil?
            ai_helper_logger.warn "validate_search_params: values is nil for field '#{field[:field_name]}'"
            errors << "values for field '#{field[:field_name]}' are required but were not provided."
            next
          end
          if field[:field_name].match(/_id$/) && field[:values].length > 0
            field[:values].each do |value|
              unless value.to_s.match(/^\d+$/)
                errors << "The #{field[:field_name]} requires a numeric value. But the value is #{value}."
              end
            end
          end
        end

        (date_fields || []).each do |field|
          if field[:field_name].nil?
            ai_helper_logger.warn "validate_search_params: field_name is nil in date_fields. field=#{field.inspect}"
            errors << "field_name is required but was not provided in date_fields."
            next
          end
          if field[:values].nil?
            ai_helper_logger.warn "validate_search_params: values is nil for date field '#{field[:field_name]}'"
            errors << "values for date field '#{field[:field_name]}' is required but was not provided."
            next
          end
          case field[:operator]
          when "=", ">=", "<=", "><"
            if field[:values].length == 0
              errors << "The #{field[:field_name]} and #{field[:operator]} requires an absolute date value. But no value is specified."
            end
            field[:values].each do |value|
              if value.nil?
                errors << "A value in '#{field[:field_name]}' is nil. All values must be non-nil strings."
                next
              end
              unless value.is_a?(String)
                errors << "A value in '#{field[:field_name]}' is not a string. All values must be non-nil strings."
                next
              end
              unless value.match(/\d{4}-\d{2}-\d{2}/)
                errors << "The #{field[:field_name]} and #{field[:operator]} requires an absolute date value in the format YYYY-MM-DD. But the value is #{value}."
              end
            end
          when "<t+", ">t+", "><t+", "t+", ">t-", "<t-", "><t-", "t-"
            if field[:values].length == 0
              errors << "The #{field[:field_name]} and #{field[:operator]} requires a relative date value. But no value is specified."
            end
            field[:values].each do |value|
              if value.nil?
                errors << "A value in '#{field[:field_name]}' is nil. All values must be non-nil strings."
                next
              end
              unless value.is_a?(String)
                errors << "A value in '#{field[:field_name]}' is not a string. All values must be non-nil strings."
                next
              end
              unless value.match(/\d+/)
                errors << "The #{field[:field_name]} and #{field[:operator]} requires a relative date value. But the value is #{value}."
              end
            end
          else
            unless field[:values].length == 0
              errors << "The #{field[:field_name]} and #{field[:operator]} does not require a value. But the value is specified."
            end
          end
        end

        errors
      end

      # IssueQueryBuilder is a class that builds a query for searching issues in Redmine.
      #
      class IssueQueryBuilder
        # Initializes a new IssueQueryBuilder instance.
        # @param params [Hash] The parameters for the query.
        # @param sort [Hash, nil] Normalized sort with :field and :direction. Defaults to id descending when nil.
        # @return [IssueQueryBuilder] The initialized IssueQueryBuilder instance.
        def initialize(params, sort: nil)
          @query = IssueQuery.new(name: "_")
          @params = params
          @sort = sort || { field: :id, direction: :desc }
          @query.column_names = [ "project", "tracker", "status", "subject", "priority", "assigned_to", "updated_on" ]
          @query.sort_criteria = [ [ @sort[:field].to_s, @sort[:direction].to_s ] ]
          # Keep the default status filter (open issues only) unless explicitly specified
        end

        # Apply filters to the query (must be called after project is set)
        # @return [void]
        def apply_filters
          @params[:fields].each do |field|
            operator = @params[:operators][field]
            values = @params[:values][field]
            @query.add_filter(field, operator, values)
          end
        end

        # Adds a custom field filter to the query.
        # @param custom_field_id [Integer] The ID of the custom field.
        # @param operator [String] The operator to use for the filter.
        # @param values [Array] The values to filter by.
        # @return [void]
        def add_custom_field_filter(custom_field_id, operator, values)
          @custom_field_filters ||= []
          @custom_field_filters << { field_id: custom_field_id, operator: operator, values: values }
        end

        # Apply custom field filters (must be called after project is set)
        # @return [void]
        def apply_custom_field_filters
          return unless @custom_field_filters

          @custom_field_filters.each do |cf|
            field = "cf_#{cf[:field_id]}"
            @query.add_filter(field, cf[:operator], cf[:values])
          end
        end

        # Execute the search and return issues
        # @param project [Project, nil] The project to search in. When nil, searches across all projects accessible to the user via AI Helper.
        # @param user [User] The user to check visibility for
        # @param limit [Integer] Maximum number of issues to return
        # @return [Array<Issue>] Array of visible issues
        def execute(project, user: User.current, limit: 50)
          setup_query(project, user)
          scope = cross_project_scope(project, @query.base_scope, user)
          scope.includes(:status, :priority, :tracker, :assigned_to, :author, :custom_values)
               .reorder(@sort[:field] => @sort[:direction]).limit(limit).to_a
        end

        # Returns the total count of matching issues
        # @param project [Project, nil] The project to search in. When nil, searches across all projects accessible to the user via AI Helper.
        # @param user [User] The user for visibility check
        # @return [Integer] Total count of matching issues
        def count(project, user: User.current)
          setup_query(project, user)
          cross_project_scope(project, @query.base_scope, user).distinct.count(:id)
        end

        private

        # Setup query with project and filters
        # @param project [Project, nil] The project to search in
        # @param user [User] The user for visibility check
        # @return [void]
        def setup_query(project, user)
          return if @query_setup_done

          @query.project = project
          @query.user = user
          apply_filters
          apply_custom_field_filters
          @query_setup_done = true
        end

        # Restrict the base scope to AI-Helper-accessible projects when no single project was given
        # @param project [Project, nil] The project passed to execute/count
        # @param scope [ActiveRecord::Relation] The query's base scope
        # @param user [User] The user for visibility check
        # @return [ActiveRecord::Relation] The (possibly restricted) scope
        def cross_project_scope(project, scope, user)
          return scope if project

          scope.where(Project.allowed_to_condition(user, :view_ai_helper))
        end
      end
    end
  end
end
