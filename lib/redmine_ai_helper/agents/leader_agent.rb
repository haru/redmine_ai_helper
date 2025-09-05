# frozen_string_literal: true
require "redmine_ai_helper/base_agent"
require "redmine_ai_helper/util/system_prompt"

module RedmineAiHelper
  module Agents
    # LeaderAgent is an agent responsible for giving instructions to other agents,
    # summarizing their responses, and providing the final answer to the user.
    class LeaderAgent < RedmineAiHelper::BaseAgent
      def initialize(params = {})
        super(params)
        @system_prompt = RedmineAiHelper::Util::SystemPrompt.new(params)
      end

      def backstory
        prompt = load_prompt("leader_agent/backstory")
        content = prompt.format
        content
      end

      def role
        "leader"
      end

      def system_prompt
        "#{@system_prompt.prompt}\n\n#{backstory}"
      end

      # Perform a user request by generating a goal and steps for the agents to follow.
      def perform_user_request(messages, option = {}, callback = nil)
        goal = generate_goal(messages)
        ai_helper_logger.debug "goal: #{goal}"
        steps = generate_steps(goal, messages)
        ai_helper_logger.debug "steps: #{steps}"

        if steps["steps"].empty? || steps["steps"].length == 1 && steps["steps"][0]["agent"] == "leader"
          return chat(messages, option, callback)
        end

        chat_room = RedmineAiHelper::ChatRoom.new(goal)
        agent_list = RedmineAiHelper::AgentList.instance
        steps["steps"].map { |step| step["agent"] }.uniq.reject { |a| a == "leader_agent" }.each do |agent|
          agent_instance = agent_list.get_agent_instance(agent, { project: @project, langfuse: langfuse })
          chat_room.add_agent(agent_instance)
        end

        chat_room.share_goal

        steps["steps"].each do |step|
          chat_room.send_task("leader", step["agent"], step["step"])
        end

        newmessages = messages
        newmessages += chat_room.messages if steps["steps"].any?
        newmessages << { role: "user", content: I18n.t("ai_helper.prompts.leader_agent.generate_final_response") }
        langfuse.create_span(name: "final_response", input: newmessages.last[:content])
        ai_helper_logger.debug "newmessages: #{newmessages}"
        answer = chat(newmessages, option, callback)
        langfuse.finish_current_span(output: answer)
        answer
      end

      # Generate a goal for the agents to follow based on the user's request.
      def generate_goal(messages)
        prompt = load_prompt("leader_agent/goal")

        newmessages = messages.dup
        newmessages << { role: "user", content: prompt.format }
        langfuse.create_span(name: "goal_generation", input: prompt.format)
        answer = chat(newmessages)
        langfuse.finish_current_span(output: answer)
        answer
      end

      # Generate steps for the agents to follow based on the goal.
      def generate_steps(goal, messages)
        agent_list = RedmineAiHelper::AgentList.instance
        ai_helper_logger.debug "agent_list: #{agent_list.list_agents}"
        agent_list_string = JSON.pretty_generate(agent_list.list_agents.reject { |a| a[:agent_name] == "leader_agent" })
        prompt = load_prompt("leader_agent/generate_steps")
        json_schema = {
          type: "object",
          properties: {
            steps: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  agent: {
                    type: "string",
                    description: "The role of the agent to assign the task to",
                  },
                  step: {
                    type: "string",
                    description: "The content of the instruction",
                  },
                },
                required: ["agent", "step"],
              },
              required: ["steps"],
            },
          },
        }

        parser = Langchain::OutputParsers::StructuredOutputParser.from_json_schema(json_schema)
        json_examples = <<~EOS

          ----

          Example JSON when appropriate agents are found:

          ```json
          {
            "steps": [
              {
                "agent": "project_agent",
                "step": "Please provide the ID of the project named 'my_project'."
              },
              {
                "agent": "issue_agent",
                "step": "Please provide the tickets related to the project ID obtained in the previous step."
              }
            ]
          }
          ```

          ----

          Example JSON when no appropriate agents are found:

          ```json
          {
            "steps": [
            ]
          }
          ```
        EOS

        prompt_text = prompt.format(
          goal: goal,
          agent_list: agent_list_string,
          format_instructions: parser.get_format_instructions,
          json_examples: json_examples,
          lang: I18n.locale.to_s,
        )

        ai_helper_logger.debug "prompt_text: #{prompt_text}"

        newmessages = messages.dup
        newmessages << { role: "user", content: prompt_text }
        langfuse.create_span(name: "steps_generation", input: prompt_text)
        json = chat(newmessages)
        fix_parser = Langchain::OutputParsers::OutputFixingParser.from_llm(
          llm: client,
          parser: parser,
        )
        fixed_json = fix_parser.parse(json)
        langfuse.finish_current_span(output: fixed_json)
        fixed_json
      end
    end
  end
end
