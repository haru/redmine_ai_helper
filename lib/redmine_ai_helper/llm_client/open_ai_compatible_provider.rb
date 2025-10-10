# frozen_string_literal: true
require_relative "base_provider"

module RedmineAiHelper
  module LlmClient
    # OpenAiCompatibleProvider is a specialized provider for OpenAI-compatible LLMs.
    class OpenAiCompatibleProvider < RedmineAiHelper::LlmClient::BaseProvider
      # Generate a client for OpenAI-compatible LLMs.
      # @return [OpenAiCompatible] The OpenAI-compatible client.
      def generate_client
        setting = AiHelperSetting.find_or_create
        model_profile = setting.model_profile
        raise "Model Profile not found" unless model_profile
        raise "Base URI not found" unless model_profile.base_uri
        llm_options = {
          uri_base: model_profile.base_uri,
        }
        llm_options[:organization_id] = model_profile.organization_id if model_profile.organization_id
        llm_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        default_options = {
          chat_model: model_profile.llm_model,
          temperature: model_profile.temperature,
        }
        default_options[:embedding_model] = setting.embedding_model unless setting.embedding_model.blank?
        default_options[:dimensions] = setting.dimension if setting.dimension
        default_options[:max_tokens] = setting.max_tokens if setting.max_tokens
        client = OpenAiCompatible.new(
          api_key: model_profile.access_key,
          llm_options: llm_options,
          default_options: default_options,
        )
        raise "OpenAI LLM Create Erro" unless client
        client
      end

      # Many LLMs with OpenAI API-compatible APIs do not implement tool calls,
      # so we implement compatibility features ourselves.
      class OpenAiCompatible < RedmineAiHelper::LangfuseUtil::OpenAi
        def initialize(**kwargs)
          super(**kwargs)
        end

        # Override the chat method to handle tool calls.
        # @param [Hash] params Parameters for the chat request.
        # @param [Proc] block Block to handle the response.
        # @return [Langchain::LLM::OpenAIResponse] The response from the chat.
        def chat(params = {}, &block)
          tools = params[:tools] || []
          messages = params[:messages] || []
          last_message = messages.last
          if tools.empty?
            response = super(params, &block)
            return response
          end
          if last_message[:role] == "tool"
            answer = send_tool_result(messages: messages)
            return answer
          end
          selected = select_tools(messages: messages, tools: tools)
          selected
        end

        # Select tools based on the provided messages and available tools.
        # @param [Array] messages Messages to analyze.
        # @param [Array] tools Available tools for selection.
        # @return [Langchain::LLM::OpenAIResponse] The response containing selected tools.
        # @raise [ArgumentError] If tools are not provided.
        def select_tools(messages:, tools:)
          json_schema = {
            type: "object",
            properties: {
              tool_calls: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    id: {
                      type: "string",
                      description: "The ID of the tool",
                    },
                    type: {
                      type: "string",
                      description: "Fixed to 'function'",
                    },
                    function: {
                      type: "object",
                      properties: {
                        name: {
                          type: "string",
                          description: "The name of the tool",
                        },
                        arguments: {
                          type: "string",
                          description: "JSON string representation of the tool's arguments",
                        },
                      },
                      required: ["name", "arguments"],
                    },
                  },
                  required: ["id", "type", "function"],
                },
              },
            },
            required: ["tool_calls"],
          }
          parser = Langchain::OutputParsers::StructuredOutputParser.from_json_schema(json_schema)
          prompt = <<~EOS
            Analyze the user's message and select the most appropriate tools to resolve the user's request.

            #{parser.get_format_instructions}

            JSON example:
            {
              "tool_calls": [
                {
                  "id": "call_rCE6Kk94VZZyUIrIlrZSH0Cr",
                  "type": "function",
                  "function": {
                    "name": "weather_tool__weather",
                    "arguments": "{\"location\": \"Tokyo\", \"date\": \"2023-10-01\"}"
                    }
                  }
                }
              ]
            }
            ----
            List of tools (JSON format):
            #{JSON.pretty_generate(tools)}}
          EOS

          new_messages = messages.dup

          # Some LLMs may throw an error if user messages are consecutive, so insert an assistant message in between.
          Langchain::Assistant::Messages::OpenAIMessage.new(role: "assistant", content: "ok").to_hash
          new_messages << Langchain::Assistant::Messages::OpenAIMessage.new(role: "user", content: prompt).to_hash
          response = chat(messages: new_messages)

          json_str = response.chat_completion
          fix_parser = Langchain::OutputParsers::OutputFixingParser.from_llm(
            llm: self,
            parser: parser,
          )
          json = fix_parser.parse(json_str)
          raw_respose = response.raw_response
          new_response = {
            "id" => raw_respose["id"],
            "object" => raw_respose["object"],
            "created" => raw_respose["created"],
            "model" => raw_respose["model"],
            "usage" => raw_respose["usage"],
            "choices" => [{
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => "",
                "tool_calls" => json["tool_calls"],
              },
              "finish_reason" => "tool_calls",
            }],
          }

          Langchain::LLM::OpenAIResponse.new(new_response)
        end

        # Process tool results from messages and generate a final response.
        # This method handles the conversion of tool execution results into a format
        # the LLM can understand and generates a response based on those results.
        # @param [Array<Hash>] messages Array of messages containing tool calls and results.
        # @return [Langchain::LLM::OpenAIResponse] The final response incorporating tool results.
        def send_tool_result(messages:)
          new_messages = []
          tool_results = []
          messages.each do |message|
            if message[:role] == "tool"
              tool_results << message
              next
            end
            if message[:content].is_a?(Array)
              new_messages << message
              next
            end
            if message[:tool_calls].is_a?(Array)
              prompt = <<~EOS
                To create a response, please execute the following tools and provide the results. Based on the results, I will create a response.
                tool:
                #{message[:tool_calls].to_json}}
              EOS
              new_messages << Langchain::Assistant::Messages::OpenAIMessage.new(role: "assistant", content: prompt).to_hash
              next
            end
          end

          prompt = <<~EOS
            The tools you specified have been executed, and the following results were obtained. Based on these results, please provide your final response.

            Tool execution results (in JSON format):
            #{JSON.pretty_generate(tool_results)}
          EOS

          new_messages << Langchain::Assistant::Messages::OpenAIMessage.new(role: "user", content: prompt).to_hash

          response = chat(messages: new_messages)
          return response
        end
      end
    end
  end
end
