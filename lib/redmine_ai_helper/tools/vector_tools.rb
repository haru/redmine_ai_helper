# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/wiki_json"
require "redmine_ai_helper/util/issue_json"

module RedmineAiHelper
  module Tools
    # VectorTools is a specialized tool for handling vector database queries Qdrant.
    class VectorTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::WikiJson
      include RedmineAiHelper::Util::IssueJson

      #   raise("The vector search functionality is not enabled.") unless vector_db_enabled?
      #   raise("limit must be between 1 and 50.") unless limit.between?(1, 50)

      define_function :ask_with_filter, description: "Ask to vector database with a query text and filter." do
        property :query, type: "string", description: "The query text to use for vector search.", required: true
        property :k, type: "integer", description: "The number of records to retrieve. Default is 10. Max is 50", required: false
        property :filter, type: "object", description: "The filter to apply to the question.", required: true do
          property :must, type: "array", description: "The must filter. All conditions must be met. AND condition.", required: false do
            item :filter_item, type: "object", description: "The filter item.", required: true do
              item :key, type: "string", description: "The key to filter.", required: true, enum: ["project_id", "tracker_id", "status_id", "priority_id", "author_id", "assigned_to_id", "created_on", "updated_on", "due_date", "version_id"]
              item :condition, type: "string", description: "The condition to filter. 'match' means exact match, 'lt' means less than, 'lte' means less than or equal to, 'gt' means greater than, 'gte' means greater than or equal to.", required: true, enum: ["match", "lt", "lte", "gt", "gte"]
              item :value, type: "string", description: "The value to filter. The value must be a string.", required: true
            end
          end
          property :should, type: "array", description: "At least one condition must be met. OR condition.", required: false do
            item :filter_item, type: "object", description: "The filter item.", required: true do
              item :key, type: "string", description: "The key to filter.", required: true, enum: ["project_id", "tracker_id", "status_id", "priority_id", "author_id", "assigned_to_id", "created_on", "updated_on", "due_date", "version_id"]
              item :condition, type: "string", description: "The condition to filter. 'match' means exact match, 'lt' means less than, 'lte' means less than or equal to, 'gt' means greater than, 'gte' means greater than or equal to.", required: true, enum: ["match", "lt", "lte", "gt", "gte"]
              item :value, type: "string", description: "The value to filter. The value must be a string.", required: true
            end
          end
          property :must_not, type: "array", description: "None of the conditions must be met. NOT operation. ", required: false do
            item :filter_item, type: "object", description: "The filter item.", required: true do
              item :key, type: "string", description: "The key to filter.", required: true, enum: ["project_id", "tracker_id", "status_id", "priority_id", "author_id", "assigned_to_id", "created_on", "updated_on", "due_date", "version_id"]
              item :condition, type: "string", description: "The condition to filter. 'match' means exact match, 'lt' means less than, 'lte' means less than or equal to, 'gt' means greater than, 'gte' means greater than or equal to.", required: true, enum: ["match", "lt", "lte", "gt", "gte"]
              item :value, type: "string", description: "The value to filter. The value must be a string.", required: true
            end
          end
        end
        property :target, type: "string", description: "The target to filter. 'issue' means issue, 'wiki' means wiki page.", required: true, enum: ["issue", "wiki"]
      end

      # Ask to vector database with a query text and filter.
      # @param query [String] The query text to use for vector search.
      # @param k [Integer] The number of issues to retrieve. Default is 10. Max is 50
      # @param filter [Hash] The filter to apply to the question.
      # @param target [String] The target to filter. 'issue' means issue, 'wiki' means wiki page.
      # @return [Array<Hash>] An array of hashes containing issue or wiki information.
      def ask_with_filter(query:, k: 10, filter: {}, target:)
        raise("The vector search functionality is not enabled.") unless vector_db_enabled?
        raise("limit must be between 1 and 50.") unless k.between?(1, 50)

        begin
          filter_json = {}
          filter_json[:must] = create_filter(filter[:must]) if filter[:must]
          filter_json[:should] = create_filter(filter[:should]) if filter[:should]
          filter_json[:must_not] = create_filter(filter[:must_not]) if filter[:must_not]

          db = vector_db(target: target)
          response = db.ask_with_filter(query: query, k: k, filter: filter_json)
          ai_helper_logger.debug("Response: #{response}")
          if target == "wiki" && response.is_a?(Array)
            wikis = []
            response.each { |item|
              id = item["wiki_id"]
              wiki = WikiPage.find_by(id: id)
              next unless wiki
              next unless wiki.visible?
              wikis << generate_wiki_data(wiki)
            }
            ai_helper_logger.debug("Filtered wikis: #{wikis}")
            return wikis
          elsif target == "issue" && response.is_a?(Array)
            issues = []
            response.each { |item|
              id = item["issue_id"]
              issue = Issue.find_by(id: id)
              next unless issue
              next unless issue.visible?
              issues << generate_issue_data(issue)
            }
            ai_helper_logger.debug("Filtered issues: #{issues}")
            return issues
          end
          response
        rescue => e
          ai_helper_logger.error("Error: #{e.message}")
          ai_helper_logger.error("Backtrace: #{e.backtrace.join("\n")}")
          raise("Error: #{e.message}")
        end
      end

      private

      # Create a filter for the Qdrant database query.
      # @param filter [Array<Hash>] The filter to create.
      # @return [Array<Hash>] The created filter.
      def create_filter(filter)
        filter_json = []
        filter.each do |f|
          item = {}
          value = f[:value]
          value = f[:value].to_i if f[:key].end_with?("_id")
          item[:key] = f[:key]
          case f[:condition]
          when "match"
            item[:match] = { value: value }
          when "lt", "lte", "gt", "gte"
            item[:rante] = {
              f[:condition] => value,
            }
          end

          filter_json << item
        end

        filter_json
      end

      # Check if the vector database is enabled.
      # @return [Boolean] True if the vector database is enabled, false otherwise.
      def vector_db_enabled?
        setting = AiHelperSetting.find_or_create
        setting.vector_search_enabled
      end

      # Get the vector database client.
      def vector_db(target:)
        return @vector_db if @vector_db
        case target
        when "issue"
          @vector_db = RedmineAiHelper::Vector::IssueVectorDb.new
        when "wiki"
          @vector_db = RedmineAiHelper::Vector::WikiVectorDb.new
        else
          raise("Invalid target: #{target}. Must be 'issue' or 'wiki'.")
        end
        @vector_db
      end
    end
  end
end
