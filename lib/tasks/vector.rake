# frozen_string_literal: true

namespace :redmine do
  namespace :plugins do
    namespace :ai_helper do
      # Rake tasks for initializing, registering, and deleting the vector DB
      namespace :vector do
        desc "Register vector data for Redmine AI Helper"
        task regist: :environment do
          if enabled?
            setting = AiHelperSetting.find_or_create
            puts "Embedding model: #{setting.embedding_model || '(default)'}"
            issue_vector_db.generate_schema
            wiki_vector_db.generate_schema
            puts "Registering vector data for Redmine AI Helper..."
            issues = Issue.order(:id).all
            puts "Issues: #{issues.count} items"
            issue_vector_db.add_datas(datas: issues)
            wikis = WikiPage.order(:id).all
            puts "Wiki Pages: #{wikis.count} items"
            wiki_vector_db.add_datas(datas: wikis)
            puts "Vector data registration completed."
          else
            puts "Vector search is not enabled. Skipping registration."
          end
        end

        desc "generate"
        task generate: :environment do
          if enabled?
            puts "Generating vector index for Redmine AI Helper..."
            issue_vector_db.generate_schema
            wiki_vector_db.generate_schema
          else
            puts "Vector search is not enabled. Skipping generation."
          end
        end

        desc "Ensure Qdrant payload indexes exist for existing collections (retrofit)"
        task ensure_indexes: :environment do
          unless enabled?
            puts "Vector search is not enabled. Skipping."
            next
          end

          mismatch_found = false

          [ issue_vector_db, wiki_vector_db ].each do |vector_db|
            puts "[#{vector_db.index_name}]"
            declarations = vector_db.payload_index_declarations.each_with_object({}) do |decl, h|
              h[decl[:field_name]] = decl[:field_schema]
            end
            existing_schema = vector_db.client.fetch_payload_schema
            results = vector_db.ensure_payload_indexes
            results.each do |field_name, state|
              expected = declarations[field_name]
              case state
              when :created, :matching
                puts "  #{field_name.ljust(15)} #{expected.ljust(9)} #{state}"
              when :mismatch
                existing = existing_schema[field_name]
                puts "  #{field_name.ljust(15)} #{expected.ljust(9)} MISMATCH (existing: #{existing}, expected: #{expected})"
                mismatch_found = true
              end
            end
          end

          if mismatch_found
            puts "ensure_indexes completed with mismatch. Manual action required."
            exit 1
          else
            puts "ensure_indexes completed."
          end
        end

        desc "Destroy vector data for Redmine AI Helper"
        task destroy: :environment do
          if enabled?
            puts "Destroying vector data for Redmine AI Helper..."
            issue_vector_db.destroy_schema
            wiki_vector_db.destroy_schema
          else
            puts "Vector search is not enabled. Skipping destruction."
          end
        end

        def issue_vector_db
          return nil unless enabled?
          @issue_vector_db ||= RedmineAiHelper::Vector::IssueVectorDb.new(llm_provider: llm_provider)
        end

        def wiki_vector_db
          return nil unless enabled?
          @wiki_vector_db ||= RedmineAiHelper::Vector::WikiVectorDb.new(llm_provider: llm_provider)
        end

        def llm_provider
          @llm_provider ||= RedmineAiHelper::LlmProvider.get_vector_llm_provider
        end

        def enabled?
          setting = AiHelperSetting.find_or_create
          setting.vector_search_enabled
        end
      end
    end
  end
end
