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
            puts I18n.t("ai_helper.vector_tasks.embedding_model", model: setting.embedding_model || "(default)")
            issue_vector_db.generate_schema
            wiki_vector_db.generate_schema
            puts I18n.t("ai_helper.vector_tasks.registering")

            ai_helper_projects = setting.vector_target_projects_relation
            issues = Issue.where(project_id: ai_helper_projects).order(:id).to_a
            puts I18n.t("ai_helper.vector_tasks.issues_count", count: issues.count)
            issue_vector_db.add_datas(datas: issues)

            wikis = WikiPage.joins(wiki: :project).where(wikis: { project_id: ai_helper_projects }).order(:id).to_a
            puts I18n.t("ai_helper.vector_tasks.wiki_pages_count", count: wikis.count)
            wiki_vector_db.add_datas(datas: wikis)

            issue_result = issue_vector_db.clean_vector_data
            puts I18n.t("ai_helper.vector_tasks.removed_issue_vector_data",
                        deleted: issue_result[:deleted], failed: issue_result[:failed])

            wiki_result = wiki_vector_db.clean_vector_data
            puts I18n.t("ai_helper.vector_tasks.removed_wiki_vector_data",
                        deleted: wiki_result[:deleted], failed: wiki_result[:failed])

            puts I18n.t("ai_helper.vector_tasks.registration_completed")
          else
            puts I18n.t("ai_helper.vector_tasks.registration_skipped")
          end
        end

        desc "Generate vector index schema for Redmine AI Helper"
        task generate: :environment do
          if enabled?
            puts I18n.t("ai_helper.vector_tasks.generating_index")
            issue_vector_db.generate_schema
            wiki_vector_db.generate_schema
          else
            puts I18n.t("ai_helper.vector_tasks.generation_skipped")
          end
        end

        desc "Ensure Qdrant payload indexes exist for existing collections (retrofit)"
        task ensure_indexes: :environment do
          unless enabled?
            puts I18n.t("ai_helper.vector_tasks.ensure_indexes_skipped")
            next
          end

          mismatch_found = false

          [ issue_vector_db, wiki_vector_db ].each do |vector_db|
            puts "[#{vector_db.index_name}]"
            declarations = vector_db.payload_index_declarations.each_with_object({}) do |decl, h|
              h[decl[:field_name]] = decl[:field_schema]
            end
            payload_result = vector_db.ensure_payload_indexes
            existing_schema = payload_result[:schema]
            payload_result[:results].each do |field_name, state|
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
            puts I18n.t("ai_helper.vector_tasks.ensure_indexes_mismatch")
            exit 1
          else
            puts I18n.t("ai_helper.vector_tasks.ensure_indexes_completed")
          end
        end

        desc "Destroy vector data for Redmine AI Helper"
        task destroy: :environment do
          if enabled?
            puts I18n.t("ai_helper.vector_tasks.destroying")
            issue_vector_db.destroy_schema
            wiki_vector_db.destroy_schema
          else
            puts I18n.t("ai_helper.vector_tasks.destruction_skipped")
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
