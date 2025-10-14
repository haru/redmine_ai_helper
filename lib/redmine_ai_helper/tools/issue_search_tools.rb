module RedmineAiHelper
  module Tools
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # A class that provides functionality to the Agent for retrieving issue information
    class IssueSearchTools < RedmineAiHelper::BaseTools
      define_function :generate_url, description: "Generate a URL for searching issues based on the filter conditions. For search items with '_id', specify the ID instead of the name of the search target. If you do not know the ID, you need to call capable_issue_properties in advance to obtain the ID." do
        property :project_id, type: "integer", description: "The project ID of the project to search in.", required: true
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
      # Generate a URL with query strings to search for issues based on filter conditions
      # @param project_id [Integer] The project ID of the project to search in.
      # @param fields [Array] Search fields for the issue.
      # @param date_fields [Array] Search fields for the issue.
      # @param time_fields [Array] Search fields for the issue.
      # @param number_fields [Array] Search fields for the issue.
      # @param text_fields [Array] Search fields for the issue.
      # @param status_field [Array] Search fields for the issue.
      # @param custom_fields [Array] Search fields for the issue.
      # @return [Hash] A hash containing the generated URL.
      # @raise [ArgumentError] If the project is not found or if there are validation errors.
      def generate_url(project_id:, fields: [], date_fields: [], time_fields: [], number_fields: [], text_fields: [], status_field: [], custom_fields: [])
        project = Project.find(project_id)

        if fields.empty? && date_fields.empty? && time_fields.empty? && number_fields.empty? && text_fields.empty? && status_field.empty? && custom_fields.empty?
          return { url: "/projects/#{project.identifier}/issues" }
        end

        validate_errors = generate_issue_search_url_validate(fields, date_fields, time_fields, number_fields, text_fields, status_field, custom_fields)
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

        url = builder.generate_query_string(project)

        { url: url }
      end

      private

      # Validate the parameters for generate_issue_search_url
      def generate_issue_search_url_validate(fields, date_fields, time_fields, number_fields, text_fields, status_field, custom_fields)
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
        include ROUTE_HELPERS

        # Initializes a new IssueQueryBuilder instance.
        # @param params [Hash] The parameters for the query.
        # @param defaults [Hash] The default parameters for the query.
        # @return [IssueQueryBuilder] The initialized IssueQueryBuilder instance.
        def initialize(params, defaults = {})
          @query = IssueQuery.new
          # @query.add_filter("set_filter", "=", "1")

          params[:fields].each do |field|
            operator = params[:operators][field]
            values = params[:values][field]
            @query.add_filter(field, operator, values)
          end
          @query.column_names = ["project", "tracker", "status", "subject", "priority", "assigned_to", "updated_on"]
          @query.sort_criteria = [["priority", "desc"], ["updated_on", "desc"]]
        end

        # Adds a custom field filter to the query.
        # @param custom_field_id [Integer] The ID of the custom field.
        # @param operator [String] The operator to use for the filter.
        # @param values [Array] The values to filter by.
        # @return [void]
        def add_custom_field_filter(custom_field_id, operator, values)
          field = "cf_#{custom_field_id}"
          @query.add_filter(field, operator, values)
        end

        # Generates a query string for the project.
        # @param project [Project] The project to generate the query string for.
        # @return [String] The generated query string.
        def generate_query_string(project)
          query_params = @query.as_params
          query_params.delete(:set_filter)
          query_string = query_params.to_query
          # "/projects/#{project.identifier}/issues?set_filter=1&#{query_string}"
          "#{project_issues_path(project)}?set_filter=1&#{query_string}"
        end
      end
    end
  end
end
