module RedmineAiHelper
  module Tools
    # A class that provides functionality to the Agent for retrieving issue information
    class IssueSearchTools < RedmineAiHelper::BaseTools
      define_function :search_issues, description: "Search issues based on the filter conditions and return matching issues. For search items with '_id', specify the ID instead of the name of the search target. If you do not know the ID, you need to call capable_issue_properties in advance to obtain the ID. Default limit is 50 issues." do
        property :project_id, type: "integer", description: "The project ID of the project to search in.", required: true
        property :limit, type: "integer", description: "Maximum number of issues to return. Default is 50.", required: false
        property :fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "string", description: "The value to search for."
            end
          end
        end
        property :date_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "string", description: "The value to search for."
            end
          end
        end
        property :time_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "string", description: "The value to search for."
            end
          end
        end
        property :number_fields, type: "array", description: "Search fields for the issue." do
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "integer", description: "The value to search for."
            end
          end
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
          item type: "object", description: "Search field for the issue." do
            property :field_name, type: "string", description: "The name of the field to search.", required: true
            property :operator, type: "string", description: "The operator to use for the search.", required: true
            property :values, type: "array", description: "The values to search for.", required: true do
              item type: "integer", description: "The value to search for."
            end
          end
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
      end
      # Search issues based on filter conditions and return matching issues
      # @param project_id [Integer] The project ID of the project to search in.
      # @param limit [Integer] Maximum number of issues to return. Default is 50.
      # @param fields [Array] Search fields for the issue.
      # @param date_fields [Array] Date search fields for the issue.
      # @param time_fields [Array] Time search fields for the issue.
      # @param number_fields [Array] Number search fields for the issue.
      # @param text_fields [Array] Text search fields for the issue.
      # @param status_field [Array] Status search fields for the issue.
      # @param custom_fields [Array] Custom field search filters.
      # @return [Hash] A hash containing issues array and total_count.
      def search_issues(project_id:, limit: 50, fields: [], date_fields: [], time_fields: [], number_fields: [], text_fields: [], status_field: [], custom_fields: [])
        limit = [limit.to_i, 1].max
        project = Project.find(project_id)

        if fields.empty? && date_fields.empty? && time_fields.empty? && number_fields.empty? && text_fields.empty? && status_field.empty? && custom_fields.empty?
          # No conditions: return open visible issues for the project (same as Redmine default)
          issues = Issue.visible(User.current).open.where(project_id: project_id)
                        .includes(:status, :priority, :tracker, :assigned_to, :author, :custom_values)
                        .order(id: :desc).limit(limit)
          total_count = Issue.visible(User.current).open.where(project_id: project_id).count
          return { issues: format_issues(issues), total_count: total_count }
        end

        validate_errors = validate_search_params(fields, date_fields, time_fields, number_fields, text_fields, status_field, custom_fields)
        raise(validate_errors.join("\n")) if validate_errors.length > 0

        params = { fields: [], operators: {}, values: {} }
        params[:fields] << "project_id"
        params[:operators]["project_id"] = "="
        params[:values]["project_id"] = [project_id.to_s]

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

        builder = IssueQueryBuilder.new(params)
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

      # Validate the parameters for the search_issues tool
      def validate_search_params(fields, date_fields, time_fields, number_fields, text_fields, status_field, custom_fields)
        errors = []

        fields.each do |field|
          if field[:field_name].match(/_id$/) && field[:values].length > 0
            field[:values].each do |value|
              unless value.to_s.match(/^\d+$/)
                errors << "The #{field[:field_name]} requires a numeric value. But the value is #{value}."
              end
            end
          end
        end

        date_fields.each do |field|
          case field[:operator]
          when "=", ">=", "<=", "><"
            if field[:values].length == 0
              errors << "The #{field[:field_name]} and #{field[:operator]} requires an absolute date value. But no value is specified."
            end
            field[:values].each do |value|
              unless value.match(/\d{4}-\d{2}-\d{2}/)
                errors << "The #{field[:field_name]} and #{field[:operator]} requires an absolute date value in the format YYYY-MM-DD. But the value is #{value}."
              end
            end
          when "<t+", ">t+", "t+", ">t-", "<t-", "t-"
            if field[:values].length == 0
              errors << "The #{field[:field_name]} and #{field[:operator]} requires a relative date value. But no value is specified."
            end
            field[:values].each do |value|
              unless value.match(/\d+/)
                errors << "The #{field[:field_name]} and #{field[:operator]} requires a relative date value. But the value is #{value}."
              end
            end
          else
            unless field[:values].length == 0
              errors << "The #{field[:name]} and #{field[:operator]} does not require a value. But the value is specified."
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
        # @return [IssueQueryBuilder] The initialized IssueQueryBuilder instance.
        def initialize(params)
          @query = IssueQuery.new(name: "_")
          @params = params
          @query.column_names = ["project", "tracker", "status", "subject", "priority", "assigned_to", "updated_on"]
          @query.sort_criteria = [["id", "desc"]]
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
        # @param project [Project] The project to search in
        # @param user [User] The user to check visibility for
        # @param limit [Integer] Maximum number of issues to return
        # @return [Array<Issue>] Array of visible issues
        def execute(project, user: User.current, limit: 50)
          setup_query(project, user)
          scope = @query.base_scope
          scope.includes(:status, :priority, :tracker, :assigned_to, :author, :custom_values)
               .order(id: :desc).limit(limit).to_a
        end

        # Returns the total count of matching issues
        # @param project [Project] The project to search in
        # @param user [User] The user to check visibility for
        # @return [Integer] Total count of matching issues
        def count(project, user: User.current)
          setup_query(project, user)
          @query.issue_count
        end

        private

        # Setup query with project and filters
        # @param project [Project] The project to search in
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
      end
    end
  end
end
