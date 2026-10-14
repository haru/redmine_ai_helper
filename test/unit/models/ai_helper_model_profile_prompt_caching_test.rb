require File.expand_path("../../../test_helper", __FILE__)

class AiHelperModelProfilePromptCachingTest < ActiveSupport::TestCase
  context "AiHelperModelProfile prompt_caching_enabled" do
    should "default to true for a new record" do
      assert_equal true, AiHelperModelProfile.new.prompt_caching_enabled
    end

    should "be active only for an Anthropic profile with caching enabled" do
      assert AiHelperModelProfile.new(llm_type: RedmineAiHelper::LlmProvider::LLM_ANTHROPIC, prompt_caching_enabled: true).prompt_caching_active?
      assert_not AiHelperModelProfile.new(llm_type: RedmineAiHelper::LlmProvider::LLM_ANTHROPIC, prompt_caching_enabled: false).prompt_caching_active?
      assert_not AiHelperModelProfile.new(llm_type: RedmineAiHelper::LlmProvider::LLM_OPENAI, prompt_caching_enabled: true).prompt_caching_active?
    end

    should "be a safe attribute" do
      assert_includes AiHelperModelProfile.new.safe_attribute_names, "prompt_caching_enabled"
    end
  end
end
