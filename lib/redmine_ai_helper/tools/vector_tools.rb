# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/wiki_json"
require "redmine_ai_helper/util/issue_json"
require "redmine_ai_helper/vector/issue_content_analyzer"

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
              next unless User.current.allowed_to?(:view_ai_helper, wiki.project)
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
              next unless User.current.allowed_to?(:view_ai_helper, issue.project)
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

      define_function :find_similar_issues, description: "Find similar issues using vector similarity search." do
        property :issue_id, type: "integer", description: "The ID of the issue to find similar issues for.", required: true
        property :k, type: "integer", description: "The number of similar issues to retrieve. Default is 10. Max is 50", required: false
      end

      # Find similar issues using vector similarity search.
      # @param issue_id [Integer] The ID of the issue to find similar issues for.
      # @param k [Integer] The number of similar issues to retrieve. Default is 10. Max is 50
      # @return [Array<Hash>] An array of hashes containing similar issues with similarity scores.
      def find_similar_issues(issue_id:, k: 10)
        raise("The vector search functionality is not enabled.") unless vector_db_enabled?
        raise("limit must be between 1 and 50.") unless k.between?(1, 50)

        begin
          ai_helper_logger.debug("Finding similar issues for issue_id: #{issue_id}, k: #{k}")

          issue = Issue.find_by(id: issue_id)
          raise("Issue not found with ID: #{issue_id}") unless issue
          raise("Permission denied") unless issue.visible?

          # Use vector database for similarity search
          ai_helper_logger.debug("Initializing vector database for issue target")
          db = vector_db(target: "issue")

          # Check if vector search is enabled and client is available
          ai_helper_logger.debug("Checking if vector search client is available")
          unless db.client
            raise("Vector search is not enabled or configured")
          end

          query = build_hybrid_query(issue)
          ai_helper_logger.debug("Performing similarity search with query: #{query[0..100]}...")

          # Search for similar issues
          results = db.similarity_search(question: query, k: k)
          ai_helper_logger.debug("Raw similarity search results: #{results&.length || 0} items")

          # Handle case where results is nil or empty
          results = [] if results.nil?

          # Filter out current issue and check permissions for each result
          similar_issues = []
          results.each do |result|
            result_issue_id = result["payload"]["issue_id"]

            # Skip current issue
            next if result_issue_id == issue_id

            # Check if the issue exists and is visible
            result_issue = Issue.find_by(id: result_issue_id)
            next unless result_issue
            next unless result_issue.visible?
            next unless User.current.allowed_to?(:view_ai_helper, result_issue.project)

            begin
              # Generate issue data using the same method as ask_with_filter
              issue_data = generate_issue_data(result_issue)
              # Add similarity score to the issue data
              issue_data[:similarity_score] = (result["score"] * 100).round(1)

              similar_issues << issue_data
            rescue => e
              ai_helper_logger.warn("Failed to generate issue data for issue #{result_issue_id}: #{e.message}")
              # Skip this issue if we can't generate its data
              next
            end
          end

          ai_helper_logger.debug("Similar issues found: #{similar_issues.length} items")
          similar_issues
        rescue => e
          ai_helper_logger.error("Error in find_similar_issues: #{e.message}")
          ai_helper_logger.error("Error class: #{e.class}")
          ai_helper_logger.error("Backtrace: #{e.backtrace.join("\n")}")
          raise("Error: #{e.message}")
        end
      end

      # Find similar issues by content (subject and description) using vector similarity search.
      # This is used for duplicate checking when creating a new issue.
      # @param subject [String] The subject of the issue.
      # @param description [String] The description of the issue.
      # @param k [Integer] The number of similar issues to retrieve. Default is 10. Max is 50
      # @return [Array<Hash>] An array of hashes containing similar issues with similarity scores.
      def find_similar_issues_by_content(subject:, description:, k: 10)
        raise("The vector search functionality is not enabled.") unless vector_db_enabled?
        raise("limit must be between 1 and 50.") unless k.between?(1, 50)

        begin
          query = build_content_query(subject, description)
          db = vector_db(target: "issue")

          unless db.client
            raise("Vector search is not enabled or configured")
          end

          ai_helper_logger.debug("Finding similar issues by content, k: #{k}")
          results = db.similarity_search(question: query, k: k)
          ai_helper_logger.debug("Raw similarity search results: #{results&.length || 0} items")

          results ||= []

          similar_issues = []
          results.each do |result|
            result_issue_id = result["payload"]["issue_id"]

            result_issue = Issue.find_by(id: result_issue_id)
            next unless result_issue
            next unless result_issue.visible?
            next unless User.current.allowed_to?(:view_ai_helper, result_issue.project)

            begin
              issue_data = generate_issue_data(result_issue)
              issue_data[:similarity_score] = (result["score"] * 100).round(1)
              similar_issues << issue_data
            rescue => e
              ai_helper_logger.warn("Failed to generate issue data for issue #{result_issue_id}: #{e.message}")
              next
            end
          end

          ai_helper_logger.debug("Similar issues found by content: #{similar_issues.length} items")
          similar_issues
        rescue => e
          ai_helper_logger.error("Error in find_similar_issues_by_content: #{e.message}")
          raise("Error: #{e.message}")
        end
      end

      private

      # Build a content query for vector similarity search from subject and description.
      # @param subject [String] The subject of the issue.
      # @param description [String] The description of the issue.
      # @return [String] The formatted query string.
      def build_content_query(subject, description)
        <<~QUERY
          Title: #{subject}
          Description: #{description}
        QUERY
      end

      # Build a hybrid query for vector similarity search.
      # Uses IssueContentAnalyzer to generate a structured query with summary, keywords, and title.
      # Falls back to raw query (subject + description) if analysis fails.
      # @param issue [Issue] The issue to build a query for.
      # @return [String] The formatted query string.
      def build_hybrid_query(issue)
        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new
        analysis = analyzer.analyze(issue)

        <<~QUERY
          Summary: #{analysis[:summary]}
          Keywords: #{analysis[:keywords].join(", ")}
          Title: #{issue.subject}
        QUERY
      rescue => e
        ai_helper_logger.warn("Failed to build hybrid query: #{e.message}, falling back to raw query")
        "#{issue.subject} #{issue.description}"
      end

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
