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
      # @param _conversation [Object] Reserved for future use; currently ignored.
      def prompt(_conversation = nil)
        return @prompt_text if @prompt_text
        current_user_info = {
          id: User.current.id,
          name: User.current.name,
          timezone: User.current.time_zone
        }
        prompt = RedmineAiHelper::Util::PromptLoader.load_template("leader_agent/system_prompt")
        @prompt_text = prompt.format(
          lang: I18n.t(:general_lang_name),
          time: Time.now.iso8601,
          site_info: site_info_json(project: @project),
          current_page_info: current_page_info_string(),
          current_user: User.current,
          current_user_info: JSON.pretty_generate(current_user_info),
          additional_system_prompt: AiHelperSetting.find_or_create.additional_instructions
        )

        @prompt_text
      end

      private

      # Generates a string that describes the current page information.
      # @return [String] A string that describes the current page information.
      # @note This method is used to provide context to the AI about the current page.
      def current_page_info_string
        page_name = case @controller_name
        when "projects" then I18n.t("ai_helper.prompts.current_page_info.project_page", project_name: @project.name)
        when "issues" then issues_page_name
        when "wiki" then wiki_page_name
        when "repositories" then repositories_page_name
        when "boards" then boards_page_name
        when "messages" then messages_page_name
        when "versions" then versions_page_name
        else I18n.t("ai_helper.prompts.current_page_info.other_page", controller_name: @controller_name, action_name: @action_name)
        end

        return "" if page_name.nil?

        <<~EOS

          ----

          Information about the Redmine page currently being viewed by the user
          Page name: #{page_name}
        EOS
      end

      def issues_page_name
        case @action_name
        when "show"
          issue = Issue.find(@content_id)
          I18n.t("ai_helper.prompts.current_page_info.issue_detail_page", issue_id: issue.id)
        when "index"
          I18n.t("ai_helper.prompts.current_page_info.issue_list_page")
        else
          I18n.t("ai_helper.prompts.current_page_info.issue_with_action_page", action_name: @action_name)
        end
      end

      def wiki_page_name
        return nil unless @action_name == "show"

        page = WikiPage.find(@content_id)
        I18n.t("ai_helper.prompts.current_page_info.wiki_page", page_title: page.title)
      end

      def repositories_page_name
        repo = Repository.find(@content_id)
        case @action_name
        when "show"
          I18n.t("ai_helper.prompts.current_page_info.repository_page", repo_name: repo.name, repo_id: repo.id)
        when "entry"
          I18n.t("ai_helper.prompts.current_page_info.repository_file_page", path: @additional_info["path"], rev: @additional_info["rev"], repo_name: repo.name, repo_id: repo.id)
        when "diff"
          repositories_diff_page_name(repo)
        when "revision"
          I18n.t("ai_helper.prompts.current_page_info.repository_revision_page", repo_name: repo.name, repo_id: repo.id, rev: @additional_info["rev"])
        else
          I18n.t("ai_helper.prompts.current_page_info.repository_other_page")
        end
      end

      def repositories_diff_page_name(repo)
        name = I18n.t("ai_helper.prompts.current_page_info.repository_diff.page", repo_name: repo.name, repo_id: repo.id)
        name += if @additional_info["rev_to"]
                  I18n.t("ai_helper.prompts.current_page_info.repository_diff.rev_to", rev: @additional_info["rev"], rev_to: @additional_info["rev_to"])
        else
                  I18n.t("ai_helper.prompts.current_page_info.repository_diff.rev", rev: @additional_info["rev"])
        end
        name += I18n.t("ai_helper.prompts.current_page_info.repository_diff.path", path: @additional_info["path"]) if @additional_info["path"]
        name
      end

      def boards_page_name
        board = Board.find(@content_id) if @content_id
        case @action_name
        when "show"
          I18n.t("ai_helper.prompts.current_page_info.boards.show", board_name: board.name, board_id: board.id)
        when "index"
          board ? I18n.t("ai_helper.prompts.current_page_info.boards.show", board_name: board.name, board_id: board.id) : I18n.t("ai_helper.prompts.current_page_info.boards.index")
        else
          I18n.t("ai_helper.prompts.current_page_info.boards.other")
        end
      end

      def messages_page_name
        message = Message.find(@content_id) if @content_id
        message ? I18n.t("ai_helper.prompts.current_page_info.messages.show", subject: message.subject, message_id: message.id) : I18n.t("ai_helper.prompts.current_page_info.messages.other")
      end

      def versions_page_name
        version = Version.find(@content_id) if @content_id
        version ? I18n.t("ai_helper.prompts.current_page_info.versions.show", version_name: version.name, version_id: version.id) : I18n.t("ai_helper.prompts.current_page_info.versions.other")
      end

      def site_info_json(param = {})
        hash = {
          site: {
            title: Setting.app_title,
            welcome_text: Setting.welcome_text,
            redmine_version: Redmine::VERSION::STRING
          }
        }

        if param[:project]
          project = param[:project]
          hash[:current_project] = {
            id: project.id,
            name: project.name,
            description: project.description,
            identifier: project.identifier,
            created_on: project.created_on

          }
        end

        JSON.pretty_generate(hash)
      end
    end
  end
end
