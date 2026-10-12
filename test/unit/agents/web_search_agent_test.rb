require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/web_search_agent"

class WebSearchAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users

  class DummyLangfuse
    def create_span(name:, input:)
    end

    def finish_current_span(output:)
    end
  end

  # A minimal stand-in for a RubyLLM::Chat that records what it was asked.
  class FakeChat
    attr_reader :provider_tool_calls, :asked

    def initialize(response)
      @response = response
      @provider_tool_calls = []
      @asked = []
    end

    def with_provider_tools(*tools)
      @provider_tool_calls << tools
      self
    end

    def after_message
      self
    end

    def ask(content)
      @asked << content
      @response
    end

    def waiting?
      false
    end
  end

  def response_with(citations, content: "answer", finish_reason: :stop)
    RubyLLM::Message.new(role: :assistant, content: content, citations: citations, finish_reason: finish_reason)
  end

  def build_provider(supported:, chat:)
    provider = mock("provider")
    provider.stubs(:supports_web_search?).returns(supported)
    provider.stubs(:model_name).returns("m")
    provider.stubs(:temperature).returns(nil)
    provider.stubs(:max_tokens).returns(nil)
    provider.stubs(:create_chat).returns(chat)
    provider
  end

  def build_agent(provider)
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(provider)
    RedmineAiHelper::Agents::WebSearchAgent.new(project: Project.find(1), langfuse: DummyLangfuse.new)
  end

  def add_task(agent, task = "From: leader\n\n----\n\nTo: web_search_agent\nfind the latest Redmine version")
    agent.add_message(role: "user", content: task)
  end

  context "WebSearchAgent" do
    should "be registered under web_search_agent" do
      assert_equal "RedmineAiHelper::Agents::WebSearchAgent", RedmineAiHelper::AgentList.instance.find_agent("web_search_agent")[:class]
    end

    should "stay enabled in read-only mode (FR-008)" do
      provider = RedmineAiHelper::LlmClient::BaseProvider.new(model_profile: AiHelperModelProfile.new(llm_type: "OpenAI"))
      agent = build_agent(provider)
      AiHelperSetting.stubs(:web_search_enabled?).returns(true)
      AiHelperSetting.stubs(:read_only_mode?).returns(true)

      assert agent.enabled?
    end

    should "have no tools" do
      agent = build_agent(build_provider(supported: true, chat: FakeChat.new(response_with([]))))
      assert_equal [], agent.available_tool_classes
    end

    context "enabled?" do
      {
        "OpenAI" => true, "Anthropic" => true, "Gemini" => true,
        "AzureOpenAi" => false, "OpenAICompatible" => false
      }.each do |llm_type, supported|
        should "be #{supported} for #{llm_type} when the setting is on and false when it is off" do
          provider = RedmineAiHelper::LlmClient::BaseProvider.new(model_profile: AiHelperModelProfile.new(llm_type: llm_type))
          agent = build_agent(provider)

          AiHelperSetting.stubs(:web_search_enabled?).returns(true)
          assert_equal supported, agent.enabled?

          AiHelperSetting.stubs(:web_search_enabled?).returns(false)
          assert_equal false, agent.enabled?
        end
      end
    end

    context "perform_task" do
      should "raise ArgumentError when there is no task" do
        agent = build_agent(build_provider(supported: true, chat: FakeChat.new(response_with([]))))
        assert_raises(ArgumentError) { agent.perform_task }
      end

      should "send only the last task and enable web search on a supporting provider" do
        chat = FakeChat.new(response_with([]))
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent, "From: leader\n\n----\n\nTo: all\nthe goal")
        add_task(agent)

        result = agent.perform_task

        assert_equal [ [ :web_search ] ], chat.provider_tool_calls
        assert_equal 1, chat.asked.size
        assert_match "find the latest Redmine version", chat.asked.first
        assert_no_match(/the goal/, chat.asked.first)
        assert_equal "answer", result.value
      end

      should "not enable web search on a provider without support" do
        chat = FakeChat.new(response_with([]))
        agent = build_agent(build_provider(supported: false, chat: chat))
        add_task(agent)

        agent.perform_task

        assert_equal [], chat.provider_tool_calls
      end

      should "decide web search support by the Think provider for use_think_model steps" do
        main_chat = FakeChat.new(response_with([]))
        think_chat = FakeChat.new(response_with([]))
        think_provider = build_provider(supported: false, chat: think_chat)
        agent = build_agent(build_provider(supported: true, chat: main_chat))
        agent.stubs(:think_llm_provider).returns(think_provider)
        add_task(agent)

        agent.perform_task(use_think_model: true)

        assert_equal [], think_chat.provider_tool_calls
        assert_equal [], main_chat.asked
        assert_equal 1, think_chat.asked.size
      end

      should "fall back to the main provider when no Think provider is configured" do
        chat = FakeChat.new(response_with([]))
        agent = build_agent(build_provider(supported: true, chat: chat))
        agent.stubs(:think_llm_provider).returns(nil)
        add_task(agent)

        agent.perform_task(use_think_model: true)

        assert_equal [ [ :web_search ] ], chat.provider_tool_calls
      end

      should "accumulate citations in call order, skipping those without a url" do
        first = response_with([
          RubyLLM::Citation.new(url: "https://example.com/a", title: "A"),
          RubyLLM::Citation.new(url: nil, title: "no url")
        ])
        second = response_with([ RubyLLM::Citation.new(url: "https://example.com/b", title: "B") ])
        chat = FakeChat.new(first)
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)
        agent.perform_task
        chat.instance_variable_set(:@response, second)
        add_task(agent)
        agent.perform_task

        assert_equal %w[https://example.com/a https://example.com/b], agent.citations.map(&:url)
      end

      should "return an error response without retrying when the request fails" do
        chat = FakeChat.new(nil)
        chat.stubs(:ask).raises(RuntimeError, "boom").once
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)

        result = agent.perform_task

        assert result.is_error?
        assert_equal "boom", result.error
        assert_equal [], agent.citations
      end

      { max_tokens: :max_tokens, content_filter: :content_filter, pause_turn: :pause_turn }.each do |name, reason|
        should "return an error response without citations when the answer was cut off by #{name}" do
          chat = FakeChat.new(response_with([ RubyLLM::Citation.new(url: "https://example.com/a", title: "A") ], finish_reason: reason))
          agent = build_agent(build_provider(supported: true, chat: chat))
          add_task(agent)

          result = agent.perform_task

          assert result.is_error?
          assert_match(/incomplete.*#{reason}/, result.error)
          assert_equal [], agent.citations
          assert_equal 1, chat.asked.size
        end
      end

      should "accept an answer without a finish reason" do
        chat = FakeChat.new(response_with([], finish_reason: nil))
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)

        assert_not agent.perform_task.is_error?
      end

      should "let an invalid citation from the provider propagate instead of becoming an error response" do
        chat = FakeChat.new(response_with([ RubyLLM::Citation.new(url: "https://example.com/a", title: 1) ]))
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)

        assert_raises(ArgumentError) { agent.perform_task }
      end

      should "return a frozen copy of the citations" do
        chat = FakeChat.new(response_with([ RubyLLM::Citation.new(url: "https://example.com/a", title: "A") ]))
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)
        agent.perform_task

        citations = agent.citations
        assert citations.frozen?
        assert_raises(FrozenError) { citations.clear }
        assert_equal 1, agent.citations.size
      end

      should "return an error response when the chat is paused" do
        chat = FakeChat.new(response_with([]))
        chat.stubs(:waiting?).returns(true)
        agent = build_agent(build_provider(supported: true, chat: chat))
        add_task(agent)

        assert agent.perform_task.is_error?
      end
    end

    context "system prompt" do
      { "en" => /personal names|e-mail/i, "ja" => /個人名|メールアドレス/ }.each do |locale, pattern|
        should "carry the search term rule in #{locale}" do
          I18n.with_locale(locale) do
            agent = build_agent(build_provider(supported: true, chat: FakeChat.new(response_with([]))))
            assert_match pattern, agent.system_prompt.to_s
          end
        end
      end
    end
  end
end
