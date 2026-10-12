# frozen_string_literal: true

require "redmine_ai_helper/base_agent"
require "redmine_ai_helper/web_citation"

module RedmineAiHelper
  module Agents
    # WebSearchAgent researches public information with the LLM provider's own web
    # search tool and collects the sources the provider returns. It has no tools
    # for Redmine data, and it is the only code path that enables web search on a
    # chat. It is offered to the leader agent only when web search is enabled in
    # the settings and the main model profile supports it.
    class WebSearchAgent < RedmineAiHelper::BaseAgent
      # @param params [Hash] Parameters for initializing the agent.
      def initialize(params = {})
        super
        @citations = []
      end

      # @return [String] The backstory prompt
      def backstory
        load_prompt("web_search_agent/backstory").format
      end

      # Whether web search is enabled in the settings and the main provider supports it.
      # @return [Boolean]
      def enabled?
        AiHelperSetting.web_search_enabled? && @llm_provider.supports_web_search?
      end

      # The sources collected by {#perform_task}, in the order the provider returned them.
      # @return [Array<RedmineAiHelper::WebCitation>] a frozen copy
      def citations
        @citations.dup.freeze
      end

      # Record a message of the chat room. The task is sent to the LLM as the only
      # message, so no assistant is built here.
      # @param role [String] The role of the message sender.
      # @param content [String] The content of the message.
      # @return [void]
      def add_message(role:, content:)
        @shared_messages << { role: role, content: content }
      end

      # Research the last task with web search and collect the sources.
      # Only the system prompt (role, backstory, language, current time) and the
      # content of the task are sent to the LLM; the goal and the results of other
      # agents in the chat room are not. A provider failure, or an answer the
      # provider cut off, becomes an error response and is neither retried nor
      # repeated without web search.
      # @param option [Hash] Options for the task (+:use_think_model+).
      # @param _callback [Proc] Reserved for future use; currently ignored.
      # @return [TaskResponse] The answer, or the error.
      # @raise [ArgumentError] when no task was added to the agent.
      def perform_task(option = {}, _callback = nil)
        raise ArgumentError, "No task has been added to the web search agent" if @shared_messages.empty?

        task = @shared_messages.last[:content]
        provider = option[:use_think_model] ? think_or_main_provider : @llm_provider
        langfuse.create_span(name: "perform_task", input: task)
        response = search(provider, task)
        langfuse.finish_current_span(output: response)
        response
      end

      private

      # Ask the provider's chat the task, with web search when the provider supports it.
      # Only the provider request is turned into an error response; errors in the
      # plugin's own code (e.g. an invalid citation) propagate.
      # @param provider [RedmineAiHelper::LlmClient::BaseProvider] The provider to use.
      # @param task [String] The content of the task.
      # @return [TaskResponse]
      def search(provider, task)
        chat_instance = provider.create_chat(instructions: system_prompt)
        setup_langfuse_callbacks(chat_instance, provider: provider)
        chat_instance.with_provider_tools(:web_search) if provider.supports_web_search?
        begin
          response = chat_instance.ask(task)
          raise_if_waiting(chat_instance)
          raise_if_incomplete(response)
        rescue => e
          ai_helper_logger.error "web search failed (provider=#{provider.class.name}, model=#{provider.model_name}): #{e.full_message}"
          return TaskResponse.create_error e.message
        end
        @citations.concat(response.citations.filter_map { |citation| WebCitation.from_ruby_llm(citation) })
        TaskResponse.create_success response.content
      end

      # Raise when the provider cut the answer off: a token limit, a safety filter,
      # or an Anthropic turn still paused after RubyLLM's automatic continuations.
      # A missing finish reason is accepted, since some OpenAI-compatible servers omit it.
      # @param response [RubyLLM::Message] The provider's answer.
      # @return [void]
      # @raise [RuntimeError] when the answer is incomplete.
      def raise_if_incomplete(response)
        return unless response.max_tokens? || response.content_filtered? || response.finish_reason == :pause_turn

        raise "The web search answer is incomplete (finish reason: #{response.finish_reason})"
      end
    end
  end
end
