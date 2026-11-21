# frozen_string_literal: true

require "ruby_llm/test_helper"
require File.expand_path("../../test_helper", __dir__)

# Pins RubyLLM 2.2's behavior for a failing MCP tool call: the failure goes back
# to the model as the tool's result and the chat goes on. The plugin adds no
# rescue of its own, so this is a guarantee test against the real stdio
# transport and the real conversation loop.
class McpToolCallFailureTest < ActiveSupport::TestCase
  include RubyLLM::TestHelper

  SERVER_PATH = File.expand_path("../../support/mcp/exits_on_tool_call_server.rb", __dir__)
  SERVER_NAME = "exits_on_call"

  setup do
    RubyLLM::MCP::Outages.clear
    @client = RubyLLM.mcp(name: SERVER_NAME, command: [ RbConfig.ruby, SERVER_PATH ], input_requests: false)
    @tools = RedmineAiHelper::Tools::McpTools.generate_tool_classes(mcp_server_name: SERVER_NAME, mcp_client: @client)
    @model_id = "gpt-4o"
  end

  teardown do
    @client&.close
    RubyLLM::MCP::Outages.clear
  end

  def build_chat
    RubyLLM.chat(model: @model_id, provider: :openai, assume_model_exists: true).with_tools(*@tools)
  end

  def tool_result_contents(chat)
    chat.messages.select { |m| m.role == :tool }.map { |m| m.content.to_s }
  end

  context "when the MCP server exits during a tool call" do
    should "give the failure to the model and finish the chat" do
      stub_replies tool_call(:echo), "final answer"

      reply = build_chat.ask("use the tool")

      assert_equal "final answer", reply.content
    end

    should "report the failing server in the tool result" do
      stub_replies tool_call(:echo), "final answer"
      chat = build_chat

      chat.ask("use the tool")

      results = tool_result_contents(chat)
      assert_equal 1, results.size
      assert_includes results.first, "The #{SERVER_NAME} MCP server failed:"
    end

    should "not reach the server again while it sits out" do
      stub_replies tool_call(:echo), tool_call(:echo), "final answer"
      chat = build_chat

      chat.ask("use the tool")

      results = tool_result_contents(chat)
      assert_equal 2, results.size
      assert_includes results.last, "can't be reached right now"
    end
  end
end
