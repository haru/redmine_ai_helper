# frozen_string_literal: true
require "redmine_ai_helper/logger"
require "redmine_ai_helper/assistant"

# Without this, Langchain logs will be output excessively
Langchain.logger.level = Logger::ERROR

module RedmineAiHelper
  # Base class for all agents.
  class BaseAgent
    attr_accessor :llm_type, :llm_provider, :client, :langfuse
    include RedmineAiHelper::Logger

    class << self
      # This method is automatically called when a subclass agent is loaded.
      # Adds the agent to the list.
      # @param subclass [Class] The subclass that is being inherited.
      # @return [void]
      def inherited(subclass)
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
          subclass.name,
        )
      end
      
      # Method to register pending dynamic classes
      def register_pending_dynamic_class(subclass, class_name)
        real_class_name = class_name.split("::").last
        agent_name = real_class_name.underscore
        agent_list = AgentList.instance
        agent_list.add_agent(
          agent_name,
          class_name,
        )
      end
    end

    # @param params [Hash] Parameters for initializing the agent.
    def initialize(params = {})
      @project = params[:project]
      @langfuse = params[:langfuse]
      @llm_provider = RedmineAiHelper::LlmProvider.get_llm_provider

      @client = @llm_provider.generate_client
      @client.langfuse = @langfuse if @langfuse
      @llm_type = RedmineAiHelper::LlmProvider.type
    end

    def langfuse
      @langfuse
    end

    # Returns the LLM client.
    def assistant
      return @assistant if @assistant
      tool_providers = available_tool_providers || []
      tools = tool_providers.map { |tool|
        tool.new
      }
      @assistant = RedmineAiHelper::AssistantProvider.get_assistant(
        llm_type: llm_type,
        llm: client,
        instructions: system_prompt,
        tools: tools,
      )
      @assistant.llm_provider = llm_provider
      @assistant
    end

    # List all tools provided by this tool provider.
    # if [] is returned, the agent will be able to use all tools.
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
    # @return [Hash] The system prompt content.
    def system_prompt
      time = Time.now.iso8601
      prompt = load_prompt("base_agent/system_prompt")
      prompt_text = prompt.format(
        role: role,
        backstory: backstory,
        time: time,
        lang: I18n.t(:general_lang_name),
      )

      return prompt_text
    end

    # List all tools provided by available tool providers.
    # @return [Array] The list of available tools.
    def available_tools
      tools = []
      available_tool_providers.each do |provider|
        tools << provider.function_schemas.to_openai_format
      end
      tools
    end

    # Chat with the assistant.
    # @param messages [Array] The messages to be sent to the assistant.
    # @param option [Hash] Additional options for the chat.
    # @param callback [Proc] A callback function to be called with each chunk of the response.
    # @return [String] The response from the assistant.
    def chat(messages, option = {}, callback = nil)
      system_prompt_message = { "role": "system", "content": system_prompt }
      chat_params = llm_provider.create_chat_param(system_prompt_message, messages)
      answer = ""
      response = client.chat(chat_params) do |chunk|
        content = llm_provider.chunk_converter(chunk) rescue nil
        if callback
          callback.call(content)
        end
        answer += content if content
      end
      answer = response.chat_completion if llm_type == RedmineAiHelper::LlmProvider::LLM_GEMINI
      answer
    end

    # Perform a task using the assistant.
    # @param option [Hash] Additional options for the task.
    # @param callback [Proc] A callback function to be called with each chunk of the response.
    # @return [Array] The result of the task.
    def perform_task(option = {}, callback = nil)
      task = assistant.messages.last
      langfuse.create_span(name: "perform_task", input: task.content)
      response = dispatch()
      langfuse.finish_current_span(output: response)
      response
    end

    # dispatch the tool
    # @return [TaskResponse] The response from the task.
    def dispatch()
      begin
        response = assistant.run(auto_tool_execution: true)

        answer = response.last.content
        res = TaskResponse.create_success answer
        res
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        TaskResponse.create_error e.message
      end
    end

    # Add a message to the assistant.
    # @param role [String] The role of the message sender.
    # @param content [String] The content of the message.
    def add_message(role:, content:)
      assistant.add_message(role: role, content: content)
    end

    private

    # Loads the prompt template from the specified name.
    # @param name [String] The name of the prompt template to be loaded.
    # @return [String] The loaded prompt template.
    def load_prompt(name)
      RedmineAiHelper::Util::PromptLoader.load_template(name)
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
        class: class_name,
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
        next if a[:class].nil? || a[:class].empty?
        
        begin
          agent = Object.const_get(a[:class]).new
          next unless agent.enabled?
          {
            agent_name: a[:name],
            backstory: agent.backstory,
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
      RedmineAiHelper::CustomLogger.instance.info("Registered agents: #{@agents.map { |a| "#{a[:name]} (#{a[:class]})" }.join(', ')}")
    end
  end
end
