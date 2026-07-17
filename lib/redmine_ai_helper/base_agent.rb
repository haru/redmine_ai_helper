# frozen_string_literal: true

require "ruby_llm"
require "redmine_ai_helper/logger"
require "redmine_ai_helper/assistant"

module RedmineAiHelper
  # Base class for all agents.
  class BaseAgent
    attr_accessor :llm_provider, :langfuse
    include RedmineAiHelper::Logger

    class << self
      # This method is automatically called when a subclass agent is loaded.
      # Adds the agent to the list.
      # @param subclass [Class] The subclass that is being inherited.
      # @return [void]
      def inherited(subclass)
        super
        # For dynamic classes, delay registration until class name is properly set
        if subclass.name.nil?
          # Store the subclass to register later when the name is set
          @pending_dynamic_classes ||= []
          @pending_dynamic_classes << subclass
          return
        end

        class_name = subclass.name
        real_class_name = class_name.split("::").last
        @myname = real_class_name.underscore
        agent_list = AgentList.instance
        agent_list.add_agent(
          @myname,
          subclass.name
        )
      end

      # Method to register pending dynamic classes
      def register_pending_dynamic_class(_subclass, class_name)
        real_class_name = class_name.split("::").last
        agent_name = real_class_name.underscore
        agent_list = AgentList.instance
        agent_list.add_agent(
          agent_name,
          class_name
        )
      end
    end

    # @param params [Hash] Parameters for initializing the agent.
    def initialize(params = {})
      @project = params[:project]
      @langfuse = params[:langfuse]
      @llm_provider = RedmineAiHelper::LlmProvider.get_llm_provider
      @shared_messages = []
    end

    # Lazily returns the Think LLM provider, creating it on first access.
    # This avoids unnecessary DB lookups when the Think model is disabled
    # or not used by a particular agent.
    def think_llm_provider
      @think_llm_provider ||= RedmineAiHelper::LlmProvider.get_think_llm_provider
    end

    # Returns the assistant instance, creating it on first access.
    # @return [RedmineAiHelper::Assistant] The assistant instance.
    def assistant
      return @assistant if @assistant
      tool_classes = available_tool_classes || []
      @assistant = RedmineAiHelper::AssistantProvider.get_assistant(
        llm_provider: @llm_provider,
        instructions: system_prompt,
        tools: tool_classes
      )
      setup_langfuse_callbacks(@assistant.chat, provider: @llm_provider)
      @assistant
    end

    # Returns the array of RubyLLM::Tool subclasses available to this agent.
    # Subclasses should override this method.
    # @return [Array<Class>] Array of RubyLLM::Tool subclasses.
    def available_tool_classes
      available_tool_providers.flat_map(&:tool_classes)
    end

    # Backward compatibility: delegates to available_tool_classes.
    def available_tool_providers
      []
    end

    # The role of the agent
    def role
      self.class.to_s.split("::").last.underscore
    end

    # The backstory of the agent
    def backstory
      raise NotImplementedError
    end

    # Whether the agent is enabled or not
    # @return [Boolean] true if the agent is enabled, false otherwise
    def enabled?
      true
    end

    # The content of the system prompt
    # @return [String] The system prompt content.
    def system_prompt
      time = Time.now.iso8601
      prompt = load_prompt("base_agent/system_prompt")
      prompt_text = prompt.format(
        role: role,
        backstory: backstory,
        time: time,
        lang: I18n.t(:general_lang_name)
      )

      prompt_text
    end

    # List all tools as OpenAI-format hashes (used by LeaderAgent backstory etc.)
    # @return [Array<Hash>] The list of available tools.
    def available_tools
      available_tool_classes.map do |tool_class|
        {
          function: {
            name: tool_class.name.demodulize.underscore,
            description: tool_class.description
          }
        }
      end
    end

    # Chat with the LLM using RubyLLM.
    # @param messages [Array<Hash>] The messages to be sent.
    # @param _option [Hash] Reserved for future use; currently ignored.
    # @param callback [Proc] A callback function to be called with each chunk of the response.
    # @param with [Array<String>, nil] Image file paths to attach to the request.
    # @return [String] The response from the LLM.
    def chat(messages, _option = {}, callback = nil, with: nil)
      chat_instance = @llm_provider.create_chat(instructions: system_prompt)
      setup_langfuse_callbacks(chat_instance, provider: @llm_provider)
      ask_with_messages(chat_instance, messages, callback, with: with)
    end

    # Chat with the Think model LLM if configured, otherwise delegates to chat().
    # NOTE: Applying Think model to the @assistant pattern (tool-use loop) is not
    # implemented. A future design would need to solve cross-provider switching combined
    # with shared conversation history (no solution exists yet).
    # @param messages [Array<Hash>] The messages to be sent.
    # @param _option [Hash] Reserved for future use; currently ignored.
    # @param callback [Proc] A callback function to be called with each chunk of the response.
    # @param with [Array<String>, nil] Image file paths to attach to the request.
    # @return [String] The response from the LLM.
    def think_chat(messages, _option = {}, callback = nil, with: nil)
      provider = think_llm_provider || @llm_provider
      chat_instance = provider.create_chat(instructions: system_prompt)
      setup_langfuse_callbacks(chat_instance, provider: provider)
      ask_with_messages(chat_instance, messages, callback, with: with)
    end

    # Obtain a schema-conforming structured response for the given messages.
    #
    # Falls back to the prompt-instruction path: a regular {chat} call returns a
    # text response that is then parsed and validated against the schema. On
    # violations, a single regeneration is requested via the chat method.
    # Native structured output (with_schema) is handled separately for capable
    # providers (see User Story 2).
    #
    # @param messages [Array<Hash>] The messages to be sent.
    # @param json_schema [Hash] The JSON schema the response must satisfy.
    # @param with [Array<String>, nil] Image file paths to attach to the request.
    # @return [Hash, Array] The schema-conforming parsed response.
    # @raise [JSON::ParserError] If the response cannot be parsed.
    # @raise [RedmineAiHelper::Util::StructuredOutputHelper::SchemaViolationError]
    #   If the response cannot be conformed to the schema.
    def structured_chat(messages, json_schema:, with: nil)
      if @llm_provider.supports_structured_output?
        return structured_chat_native(messages, json_schema: json_schema, with: with)
      end

      response = chat(messages, {}, nil, with: with)
      RedmineAiHelper::Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: json_schema,
        chat_method: ->(retry_messages) { chat(retry_messages, {}, nil, with: with) },
        messages: messages
      )
    end

    # Return the format-instruction text appropriate for the active provider.
    #
    # Native structured-output providers enforce the schema at the API level, so
    # no format instructions are embedded in the prompt. Non-native providers
    # use the prompt-instruction text generated from the schema.
    # @param json_schema [Hash] The JSON schema.
    # @return [String] Empty string for native providers; otherwise the
    #   prompt-instruction text.
    def format_instructions_for(json_schema)
      return "" if @llm_provider.supports_structured_output?
      RedmineAiHelper::Util::StructuredOutputHelper.get_format_instructions(json_schema)
    end

    # Perform a task using the assistant.
    # When use_think_model: true, builds a fresh think assistant with shared context.
    # @param option [Hash] Additional options for the task.
    # @param _callback [Proc] Reserved for future use; currently ignored.
    # @return [TaskResponse] The response from the task.
    def perform_task(option = {}, _callback = nil)
      active_assistant = option[:use_think_model] ? build_think_assistant : assistant
      task = active_assistant.messages.last
      langfuse.create_span(name: "perform_task", input: task.content)
      response = dispatch(active_assistant)
      langfuse.finish_current_span(output: response)
      response
    end

    # Dispatch the tool using the given assistant.
    # @param active_assistant [RedmineAiHelper::Assistant] The assistant to use.
    # @return [TaskResponse] The response from the task.
    def dispatch(active_assistant = assistant)
      begin
        response = active_assistant.run(auto_tool_execution: true)

        answer = response.last.content
        res = TaskResponse.create_success answer
        res
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        TaskResponse.create_error e.message
      end
    end

    # Add a message to the assistant and track it in @shared_messages for think-model replay.
    # @param role [String] The role of the message sender.
    # @param content [String] The content of the message.
    def add_message(role:, content:)
      @shared_messages << { role: role, content: content }
      assistant.add_message(role: role, content: content)
    end

    private

    # Build message history and ask the last message on a chat instance.
    # Shared by chat, think_chat and structured_chat.
    # @param chat_instance [RubyLLM::Chat] The chat instance (already configured
    #   with instructions, callbacks, schema, etc.).
    # @param messages [Array<Hash>] The messages to send. All but the last are
    #   added as history; the last is sent via ask.
    # @param callback [Proc, nil] Optional streaming callback.
    # @param with [Array<String>, nil] Image file paths to attach to the request.
    # @return [String, Hash, Array] The assembled answer when streaming; the raw
    #   response content when not streaming, which is a Hash/Array instead of a
    #   String when native structured output (with_schema) is in effect.
    def ask_with_messages(chat_instance, messages, callback, with:)
      # Add message history (all except the last message)
      messages[0..-2].each do |msg|
        chat_instance.add_message(role: msg[:role].to_sym, content: msg[:content])
      end

      # Ask with the last message (with streaming support)
      last_message = messages.last
      ask_options = {}
      ask_options[:with] = with if with.present?
      answer = ""

      if callback
        chat_instance.ask(last_message[:content], **ask_options) do |chunk|
          content = chunk.content
          if content
            callback.call(content)
            answer += content
          end
        end
      else
        response = chat_instance.ask(last_message[:content], **ask_options)
        answer = response.content
      end

      answer
    end

    # Native structured-output path: delegate schema enforcement to the provider
    # via +with_schema+. The response content (Hash/Array or String) is fed into
    # the shared conform→validate pipeline so that any residual deviation is still
    # caught (research.md R4). Regeneration falls back to the prompt-instruction
    # +chat+ method (no schema, original attachments preserved) to recover from
    # provider-side misfires.
    #
    # Array-rooted schemas are wrapped into an object under a single property
    # before being sent as the native schema payload, and the response is
    # unwrapped back into a bare array before entering the parse pipeline,
    # because providers such as OpenAI require an object root for native
    # structured output (see StructuredOutputHelper#wrap_array_root_schema).
    def structured_chat_native(messages, json_schema:, with: nil)
      helper = RedmineAiHelper::Util::StructuredOutputHelper
      array_root = helper.array_root_schema?(json_schema)
      native_schema = array_root ? helper.wrap_array_root_schema(json_schema) : json_schema
      schema_payload = helper.native_schema_payload(native_schema)
      chat_instance = @llm_provider.create_chat(instructions: system_prompt, schema: schema_payload)
      setup_langfuse_callbacks(chat_instance, provider: @llm_provider)
      response_content = ask_with_messages(chat_instance, messages, nil, with: with)
      response_content = helper.unwrap_array_root(response_content) if array_root
      helper.parse(
        response: response_content,
        json_schema: json_schema,
        chat_method: ->(retry_messages) { chat(retry_messages, {}, nil, with: with) },
        messages: messages
      )
    end

    # Build a fresh assistant using the think LLM provider (or fall back to the regular provider).
    # Replays @shared_messages so the think model has full conversation context.
    # A fresh assistant is used rather than reusing @assistant to avoid stale provider-specific
    # tool-call state that cannot be safely copied across providers.
    # @return [RedmineAiHelper::Assistant]
    def build_think_assistant
      provider = think_llm_provider || @llm_provider
      think_asst = RedmineAiHelper::AssistantProvider.get_assistant(
        llm_provider: provider,
        instructions: system_prompt,
        tools: available_tool_classes
      )
      setup_langfuse_callbacks(think_asst.chat, provider: provider)
      @shared_messages.each do |msg|
        think_asst.add_message(role: msg[:role], content: msg[:content])
      end
      think_asst
    end

    # Set up Langfuse callbacks on a RubyLLM::Chat instance.
    # Registers an on_end_message callback that creates Langfuse generations
    # for each assistant response with token usage data.
    # @param chat_instance [RubyLLM::Chat] The chat instance to register callbacks on.
    # @param provider [Object] The LLM provider used for this chat (for model name logging).
    def setup_langfuse_callbacks(chat_instance, provider: @llm_provider)
      return unless langfuse

      chat_instance.on_end_message do |message|
        next unless message && message.role == :assistant
        next unless langfuse.current_span

        span = langfuse.current_span
        usage = {}
        if message.input_tokens
          usage = {
            prompt_tokens: message.input_tokens,
            completion_tokens: message.output_tokens,
            total_tokens: (message.input_tokens || 0) + (message.output_tokens || 0)
          }
        end

        # Collect input messages (all messages before the current response)
        # Extract text-only content from Content objects to avoid binary image data in JSON serialization
        input_messages = chat_instance.messages[0..-2].map do |m|
          { role: m.role.to_s, content: extract_text_content(m.content) }
        end

        # Determine output: use content if available, otherwise represent tool calls.
        # RubyLLM tool_calls is a Hash { call_id => ToolCall }, so use .values to get ToolCall objects.
        output = extract_text_content(message.content)
        if output.nil? && message.tool_calls
          output = message.tool_calls.values.map(&:to_h).to_json
        end

        span.create_generation(
          name: "chat",
          messages: input_messages,
          model: provider.model_name,
          temperature: provider.temperature,
          max_tokens: provider.max_tokens
        )&.finish(output: output, usage: usage)
      end
    end

    # Loads the prompt template from the specified name.
    # @param name [String] The name of the prompt template to be loaded.
    # @return [String] The loaded prompt template.
    def load_prompt(name)
      RedmineAiHelper::Util::PromptLoader.load_template(name)
    end

    # Extracts text content from a message content value.
    # When content is a RubyLLM::Content object (e.g., containing image attachments),
    # returns only the text portion to avoid binary data in JSON serialization.
    # @param content [String, RubyLLM::Content, nil] The message content
    # @return [String, nil] The text content
    def extract_text_content(content)
      if content.is_a?(RubyLLM::Content)
        content.text
      else
        content
      end
    end

    # Response class for agent tasks
    class TaskResponse < RedmineAiHelper::ToolResponse
    end
  end

  # Singleton list manager for all registered agents
  class AgentList
    include Singleton

    def initialize
      @agents = []
    end

    # Add an agent to the list
    # @param name [String] The agent name
    # @param class_name [String] The agent class name
    def add_agent(name, class_name)
      agent = {
        name: name,
        class: class_name
      }
      @agents.delete_if { |a| a[:name] == name }
      @agents << agent
    end

    # Get an agent instance by name
    # @param name [String] The agent name
    # @param option [Hash] Options to pass to the agent constructor
    # @return [BaseAgent] The agent instance
    def get_agent_instance(name, option = {})
      agent_name = name
      agent_name = "leader_agent" if name == "leader"
      agent = find_agent(agent_name)
      raise "Agent not found: #{agent_name}" unless agent
      agent_class = Object.const_get(agent[:class])
      agent_class.new(option)
    end

    # List all enabled agents
    # @return [Array<Hash>] Array of agent information
    def list_agents
      @agents.filter_map { |a|
        # Skip if class name is nil or empty
        next if a[:class].blank?

        begin
          agent = Object.const_get(a[:class]).new
          next unless agent.enabled?
          {
            agent_name: a[:name],
            backstory: agent.backstory
          }
        rescue NameError => e
          # Skip agents whose classes don't exist or can't be loaded
          RedmineAiHelper::CustomLogger.instance.warn("Cannot load agent class '#{a[:class]}': #{e.message}")
          next
        end
      }
    end

    # Find an agent by name
    # @param name [String] The agent name
    # @return [Hash, nil] The agent information or nil
    def find_agent(name)
      @agents.find { |a| a[:name] == name }
    end

    # Remove an agent from the list
    # @param name [String] The agent name
    def remove_agent(name)
      @agents.delete_if { |a| a[:name] == name }
    end

    # Get debug information about all agents
    # @return [Array<Hash>] Array of agent debug information
    def debug_agents
      RedmineAiHelper::CustomLogger.instance.info("Registered agents: #{@agents.map { |a| "#{a[:name]} (#{a[:class]})" }.join(", ")}")
    end
  end
end
