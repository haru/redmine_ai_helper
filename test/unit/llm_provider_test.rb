# filepath: lib/redmine_ai_helper/llm_provider_test.rb
require File.expand_path("../../test_helper", __FILE__)

class LlmProviderTest < ActiveSupport::TestCase
  context "LlmProvider" do
    setup do
      @llm_provider = RedmineAiHelper::LlmProvider
    end

    should "return correct options for select" do
      expected_options = [
        ["OpenAI", "OpenAI"],
        ["OpenAI Compatible(Experimental)", "OpenAICompatible"],
        ["Gemini(Experimental)", "Gemini"],
        ["Anthropic", "Anthropic"],
        ["Azure OpenAI(Experimental)", "AzureOpenAi"],
      ]
      assert_equal expected_options, @llm_provider.option_for_select
    end

    context "get_llm_provider" do
      setup do
        @setting = AiHelperSetting.find_or_create
      end
      teardown do
        @setting.model_profile.llm_type = "OpenAI"
        @setting.model_profile.save!
      end

      should "return OpenAiProvider when OpenAI is selected" do
        @setting.model_profile.llm_type = "OpenAI"
        @setting.model_profile.save!

        provider = @llm_provider.get_llm_provider
        assert_instance_of RedmineAiHelper::LlmClient::OpenAiProvider, provider
      end

      should "return GeminiProvider when Gemini is selected" do
        @setting.model_profile.llm_type = "Gemini"
        @setting.model_profile.save!
        provider = @llm_provider.get_llm_provider
        assert_instance_of RedmineAiHelper::LlmClient::GeminiProvider, provider
      end

      should "raise NotImplementedError when Anthropic is selected" do
        @setting.model_profile.llm_type = "Anthropic"
        @setting.model_profile.save!
        provider = @llm_provider.get_llm_provider
        assert_instance_of RedmineAiHelper::LlmClient::AnthropicProvider, provider
      end

      should "raise NotImplementedError when an unknown LLM is selected" do
        @setting.model_profile.llm_type = "Unknown"
        @setting.model_profile.save!
        assert_raises(NotImplementedError) do
          @llm_provider.get_llm_provider
        end
      end
    end
  end
end
