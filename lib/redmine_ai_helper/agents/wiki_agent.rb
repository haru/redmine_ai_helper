# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # WikiAgent is a specialized agent for handling Redmine wiki-related queries.
      include RedmineAiHelper::Util::WikiJson

    class WikiAgent < RedmineAiHelper::BaseAgent
      def backstory
        prompt = load_prompt("wiki_agent/backstory")
        content = prompt.format
        content
      end

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

  def generate_wiki_completion(text:, cursor_position: nil, project: nil, wiki_page: nil)
    begin
      context = build_wiki_completion_context(text, project, wiki_page)
      
      prompt = load_prompt("wiki_agent/wiki_inline_completion")
      
      prefix_text = cursor_position ? text[0...cursor_position] : text
      suffix_text = (cursor_position && cursor_position < text.length) ? text[cursor_position..-1] : ""
      
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
        related_pages: context[:related_pages] || 'None'
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

  def build_wiki_completion_context(text, project, wiki_page)
    context = {
      page_title: wiki_page&.title || 'New Wiki Page',
      project_name: project&.name,
      text_length: text.length
    }
    
    if project
      context[:project_description] = project.description if project.description.present?
      context[:project_identifier] = project.identifier
      
      context.merge!(build_existing_wiki_context(project, wiki_page))
    end
    
    context
  end

  def build_existing_wiki_context(project, current_wiki_page)
    wiki_context = {}
    
    return wiki_context unless project.wiki
    
    if current_wiki_page&.content
      existing_text = current_wiki_page.content.text
      wiki_context[:existing_content] = existing_text.present? ? existing_text[0..999] : ''
    end
    
    related_pages = project.wiki.pages
                           .where.not(id: current_wiki_page&.id)
                           .joins(:content)
                           .where.not(wiki_contents: { text: ['', nil] })
                           .order(updated_on: :desc)
                           .limit(5)
    
    if related_pages.any?
      pages_info = related_pages.map do |page|
        content_preview = page.content.text[0..200]
        "#{page.title}: #{content_preview}..."
      end
      wiki_context[:related_pages] = pages_info.join("\n\n")
    end
    
    wiki_context
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
