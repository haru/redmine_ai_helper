# RedmineAIHelper
module RedmineAiHelper
  module Util
    # A class that generates a system prompt for the Leader Agent.
    # Generates a prompt that includes information about the page the user is currently viewing.
    class SystemPrompt
      # Constructor
      # @param option [Hash] Includes project information, user information, page information, etc.
      def initialize(option = {})
        @controller_name = option[:controller_name]
        @action_name = option[:action_name]
        @content_id = option[:content_id]
        @additional_info = option[:additional_info]
        @project = option[:project]
      end

      # Generates a system prompt for the Leader Agent.
      # @param conversation [Object] The conversation object (optional). TODO: Not being used
      def prompt(conversation = nil)
        return @prompt_text if @prompt_text
        current_user_info = {
          id: User.current.id,
          name: User.current.name,
          timezone: User.current.time_zone,
        }
        prompt = RedmineAiHelper::Util::PromptLoader.load_template("leader_agent/system_prompt")
        @prompt_text = prompt.format(
          lang: I18n.t(:general_lang_name),
          time: Time.now.iso8601,
          site_info: site_info_json(project: @project),
          current_page_info: current_page_info_string(),
          current_user: User.current,
          current_user_info: JSON.pretty_generate(current_user_info),
          additional_system_prompt: AiHelperSetting.find_or_create.additional_instructions,
        )

        @prompt_text
      end

      private

      # Generates a string that describes the current page information.
      # @return [String] A string that describes the current page information.
      # @note This method is used to provide context to the AI about the current page.
      def current_page_info_string()
        page_name = nil
        case @controller_name
        when "projects"
          page_name = I18n.t("ai_helper.prompts.current_page_info.project_page", project_name: @project.name)
        when "issues"
          case @action_name
          when "show"
            issue = Issue.find(@content_id)
            page_name = I18n.t("ai_helper.prompts.current_page_info.issue_detail_page", issue_id: issue.id)
          when "index"
            page_name = I18n.t("ai_helper.prompts.current_page_info.issue_list_page")
          else
            page_name = I18n.t("ai_helper.prompts.current_page_info.issue_with_action_page", action_name: @action_name)
          end
        when "wiki"
          case @action_name
          when "show"
            page = WikiPage.find(@content_id)
            page_name = I18n.t("ai_helper.prompts.current_page_info.wiki_page", page_title: page.title)
          end
        when "repositories"
          repo = Repository.find(@content_id)
          case @action_name
          when "show"
            page_name = I18n.t("ai_helper.prompts.current_page_info.repository_page", repo_name: repo.name, repo_id: repo.id)
          when "entry"
            page_name = I18n.t("ai_helper.prompts.current_page_info.repository_file_page", path: @additional_info["path"], rev: @additional_info["rev"], repo_name: repo.name, repo_id: repo.id)
          when "diff"
            page_name = I18n.t("ai_helper.prompts.current_page_info.repository_diff.page", repo_name: repo.name, repo_id: repo.id)

            if @additional_info["rev_to"]
              page_name += I18n.t("ai_helper.prompts.current_page_info.repository_diff.rev_to", rev: @additional_info["rev"], rev_to: @additional_info["rev_to"])
            else
              page_name += I18n.t("ai_helper.prompts.current_page_info.repository_diff.rev", rev: @additional_info["rev"])
            end

            page_name += I18n.t("ai_helper.prompts.current_page_info.repository_diff.path", path: @additional_info["path"]) if @additional_info["path"]
          when "revision"
            page_name = I18n.t("ai_helper.prompts.current_page_info.repository_revision_page", repo_name: repo.name, repo_id: repo.id, rev: @additional_info["rev"])
          else
            page_name = I18n.t("ai_helper.prompts.current_page_info.repository_other_page")
          end
        when "boards"
          board = Board.find(@content_id) if @content_id
          case @action_name
          when "show"
            page_name = I18n.t("ai_helper.prompts.current_page_info.boards.show", board_name: board.name, board_id: board.id)
          when "index"
            if board
              page_name = I18n.t("ai_helper.prompts.current_page_info.boards.show", board_name: board.name, board_id: board.id)
            else
              page_name = I18n.t("ai_helper.prompts.current_page_info.boards.index")
            end
          else
            page_name = I18n.t("ai_helper.prompts.current_page_info.boards.other")
          end
        when "messages"
          message = Message.find(@content_id) if @content_id
          if message
            page_name = I18n.t("ai_helper.prompts.current_page_info.messages.show", subject: message.subject, message_id: message.id)
          else
            page_name = I18n.t("ai_helper.prompts.current_page_info.messages.other")
          end
        when "versions"
          version = Version.find(@content_id) if @content_id
          if version
            page_name = I18n.t("ai_helper.prompts.current_page_info.versions.show", version_name: version.name, version_id: version.id)
          else
            page_name = I18n.t("ai_helper.prompts.current_page_info.versions.other")
          end
        else
          page_name = I18n.t("ai_helper.prompts.current_page_info.other_page", controller_name: @controller_name, action_name: @action_name)
        end

        return "" if page_name.nil?
        string = <<~EOS

          ----

          Information about the Redmine page currently being viewed by the user
          Page name: #{page_name}
        EOS

        string
      end

      def site_info_json(param = {})
        hash = {
          site: {
            title: Setting.app_title,
            welcome_text: Setting.welcome_text,
            redmine_version: Redmine::VERSION::STRING,
          },
        }

        if param[:project]
          project = param[:project]
          hash[:current_project] = {
            id: project.id,
            name: project.name,
            description: project.description,
            identifier: project.identifier,
            created_on: project.created_on,

          }
        end

        JSON.pretty_generate(hash)
      end
    end
  end
end
