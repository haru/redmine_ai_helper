# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # WikiAgent is a specialized agent for handling Redmine wiki-related queries
    class WikiAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Util::WikiJson
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("wiki_agent/backstory")
        content = prompt.format
        content
      end

      # Get available tool providers for this agent
      # @return [Array<Class>] Array of tool provider classes
      def available_tool_providers
        base_tools = [RedmineAiHelper::Tools::WikiTools]
        if AiHelperSetting.vector_search_enabled?
          base_tools.unshift(RedmineAiHelper::Tools::VectorTools)
        end
        base_tools
      end

      # Generate a summary of the given wiki page with optional streaming support
      # @param wiki_page [WikiPage] The wiki page to summarize
      # @param stream_proc [Proc] Optional callback proc for streaming content
      # @return [String] The summary content
      def wiki_summary(wiki_page:, stream_proc: nil)
        prompt = load_prompt("wiki_agent/summary")
        prompt_text = prompt.format(
          title: wiki_page.title,
          content: wiki_page.content.text,
          project_name: wiki_page.wiki.project.name
        )

        message = { role: "user", content: prompt_text }
        messages = [message]
        chat(messages, {}, stream_proc)
      end

      # Generate wiki completion suggestions
      # @param text [String] The current text
      # @param cursor_position [Integer] The cursor position
      # @param project [Project] The project
      # @param wiki_page [WikiPage] The wiki page
      # @param is_section_edit [Boolean] Whether this is a section edit
      # @return [String] The completion suggestion
      def generate_wiki_completion(text:, cursor_position: nil, project: nil, wiki_page: nil,
                           is_section_edit: false)
        begin
          context = build_wiki_completion_context(text, project, wiki_page,
                                                is_section_edit: is_section_edit)

          prompt = load_prompt("wiki_agent/wiki_inline_completion")

          prefix_text = cursor_position ? text[0...cursor_position] : text
          suffix_text = (cursor_position && cursor_position < text.length) ? text[cursor_position..-1] : ""

          # Determine editing mode text based on locale
          editing_mode = is_section_edit ? 'Section Edit' : 'Full Page Edit'


          template_vars = {
            prefix_text: prefix_text,
            suffix_text: suffix_text,
            page_title: context[:page_title] || 'New Wiki Page',
            project_name: context[:project_name] || 'Unknown Project',
            cursor_position: cursor_position.to_s,
            max_sentences: '5',
            format: Setting.text_formatting,
            project_description: context[:project_description] || '',
            existing_content: context[:existing_content] || '',
            is_section_edit: editing_mode
          }

          prompt_text = prompt.format(**template_vars)

          message = { role: "user", content: prompt_text }
          messages = [message]

          completion = chat(messages, {})

          ai_helper_logger.debug "Generated wiki completion: #{completion.length} characters"

          parse_wiki_completion_response(completion)
        rescue => e
          ai_helper_logger.error "Wiki completion error in WikiAgent: #{e.message}"
          ai_helper_logger.error "Error backtrace: #{e.backtrace.join("\n")}"
          ""
        end
      end

      private

      def build_wiki_completion_context(text, project, wiki_page, is_section_edit: false)
    context = {
      page_title: wiki_page&.title || 'New Wiki Page',
      project_name: project&.name,
      text_length: text.length,
      is_section_edit: is_section_edit
    }

    if project
      context[:project_description] = project.description if project.description.present?
      context[:project_identifier] = project.identifier
    end

    # Only include existing wiki context for section editing
    if is_section_edit
      context.merge!(build_existing_wiki_context(project, wiki_page))
    else
      context[:existing_content] = ''
    end

    context
  end

  def build_existing_wiki_context(project, current_wiki_page)
    wiki_context = {
      existing_content: ''
    }

    return wiki_context unless project&.wiki

    if current_wiki_page&.content
      wiki_context[:existing_content] = current_wiki_page.content.text || ''
    end

    wiki_context
  end

  def truncate_content(content, max_length)
    return content if content.length <= max_length
    content[0...max_length] + "..."
  end

  def parse_wiki_completion_response(response)
    return "" if response.blank?

    cleaned_response = response.strip

    cleaned_response = cleaned_response.gsub(/\n{3,}/, "\n\n")

    cleaned_response = cleaned_response.gsub(/^[*-]+\s*/, '')
                                     .gsub(/\s*[*-]+$/, '')

    sentences = cleaned_response.split(/[.!?。！？]\s+/)
    if sentences.length > 5
      cleaned_response = sentences[0..4].join('. ') + '.'
    end

    cleaned_response = cleaned_response[0..499] if cleaned_response.length > 500

    cleaned_response
  end
    end
  end
end
