# frozen_string_literal: true

require "redmine_ai_helper/logger"

module RedmineAiHelper
  # A class representing a chat room where the LeaderAgent and other agents collaborate to achieve the user's goal.
  # The chat room is created by the LeaderAgent, and additional agents are added as needed.
  class ChatRoom
    include RedmineAiHelper::Logger
    attr_accessor :agents, :messages, :step_results

    # @param goal [String] The user's goal.
    def initialize(goal)
      @agents = []
      @goal = goal
      @messages = []
      @step_results = []
    end

    # Share the user's goal with all agents in the chat room.
    def share_goal
      first_message = <<~EOS
        The user's goal is as follows. Collaborate with all agents to achieve this goal.

        ----

        goal:
        #{goal}
      EOS
      add_message("user", "leader", first_message, "all")
    end

    # @return [String] The user's goal.
    def goal
      @goal
    end

    # Add an agent to the chat room.
    # @param agent [BaseAgent] The agent to be added to the chat room.
    # @return [Array] The list of agents in the chat room.
    def add_agent(agent)
      @agents << agent
    end

    # Add a message to the chat room.
    # @param llm_role [String] The role for the LLM (user/assistant)
    # @param from [String] The sender of the message
    # @param message [String] The message content
    # @param to [String] The recipient of the message
    # @return [Array] The list of messages in the chat room
    def add_message(llm_role, from, message, to)
      ai_helper_logger.debug "from: #{from}\n @#{to}, #{message}"
      @messages ||= []
      content = "From: #{from}\n\n----\n\nTo: #{to}\n#{message}"
      @messages << { role: llm_role, content: content }
      @agents.each do |agent|
        agent.add_message(role: llm_role, content: content)
      end
    end

    # Get an agent by its role.
    # @param [String] role The role of the agent to be retrieved.
    # @return [BaseAgent] The agent with the specified role.
    def get_agent(role)
      @agents.find { |agent| agent.role == role }
    end

    # Send a task from one agent to another. The task is saved in the messages.
    # @param [String] from the role of the agent sending the task
    # @param [String] to the role of the agent receiving the task
    # @param [String] task the task to be sent
    # @param [Hash] option options for the task
    # @param [Proc] proc a block to be executed after the task is sent
    # @return [String] the response from the agent
    def send_task(from, to, task, option = {}, proc = nil)
      add_message("user", from, task, to)
      agent = get_agent(to)
      unless agent
        error = "Agent not found: #{to}"
        ai_helper_logger.error error
        raise error
      end
      answer = agent.perform_task(option, proc)
      add_message("assistant", to, answer, from)
      record_step_result(agent: to, step: task, response: answer)
      answer
    end

    # Record a step that was skipped without calling the assigned agent (no LLM call).
    # The skip is also added to the shared message history: agents handling later steps
    # would otherwise assume this step completed and act on results that do not exist.
    # @param agent [String] The name of the agent the step was assigned to
    # @param step [String] The instruction content of the step
    # @param error [String] The reason the step was skipped
    # @return [void]
    def record_skipped_step(agent:, step:, error:)
      @step_results << { agent: agent, step: step, status: RedmineAiHelper::ToolResponse::STATUS_ERROR, error: error }
      notice = <<~EOS
        The following step was not executed, and produced no result:

        #{step}

        Reason: #{error}
      EOS
      add_message("assistant", agent, notice, "all")
    end

    # Format the accumulated step results as a JSON array string, in plan order.
    # @return [String] JSON array of step results
    def execution_results_json
      @step_results.to_json
    end

    private

    # Record the outcome of a step executed via send_task.
    # @param agent [String] The name of the agent that executed the step
    # @param step [String] The instruction content of the step
    # @param response [RedmineAiHelper::ToolResponse] The response returned by the agent
    # @return [void]
    def record_step_result(agent:, step:, response:)
      result = { agent: agent, step: step, status: response.status }
      result[:error] = response.error if response.is_error?
      @step_results << result
    end
  end
end
