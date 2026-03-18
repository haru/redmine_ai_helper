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

    context "get_think_llm_provider" do
      setup do
        @setting = AiHelperSetting.find_or_create
        @think_profile = AiHelperModelProfile.create!(
          name: "Think Profile",
          llm_model: "claude-3-7-sonnet",
          access_key: "key",
          temperature: 0.7,
          base_uri: "https://api.anthropic.com",
          max_tokens: 4096,
          llm_type: RedmineAiHelper::LlmProvider::LLM_ANTHROPIC,
        )
      end

      teardown do
        @setting.update!(use_think_model: false, think_model_profile_id: nil)
        @think_profile.destroy if @think_profile.persisted?
      end

      should "return nil when use_think_model is false" do
        @setting.update!(use_think_model: false, think_model_profile_id: nil)
        assert_nil @llm_provider.get_think_llm_provider
      end

      should "return nil when use_think_model is true but think_model_profile_id is nil" do
        @setting.update_columns(use_think_model: true, think_model_profile_id: nil)
        assert_nil @llm_provider.get_think_llm_provider
      end

      should "return correct provider type when fully configured" do
        @setting.update!(use_think_model: true, think_model_profile_id: @think_profile.id)
        provider = @llm_provider.get_think_llm_provider
        assert_not_nil provider
        assert_instance_of RedmineAiHelper::LlmClient::AnthropicProvider, provider
      end

      should "raise ActiveRecord::RecordNotFound when profile no longer exists" do
        @setting.update_columns(use_think_model: true, think_model_profile_id: 999999)
        assert_raises(ActiveRecord::RecordNotFound) do
          @llm_provider.get_think_llm_provider
        end
      end

      should "return provider with think model's model_name, not regular model's" do
        @setting.update!(use_think_model: true, think_model_profile_id: @think_profile.id)
        provider = @llm_provider.get_think_llm_provider
        assert_equal @think_profile.llm_model, provider.model_name
        refute_equal @setting.model_profile.llm_model, provider.model_name
      end

      should "return provider with think model's temperature" do
        @setting.update!(use_think_model: true, think_model_profile_id: @think_profile.id)
        provider = @llm_provider.get_think_llm_provider
        assert_equal @think_profile.temperature, provider.temperature
      end
    end

    context "get_vector_llm_provider" do
      setup do
        @setting = AiHelperSetting.find_or_create
        @vector_profile = AiHelperModelProfile.create!(
          name: "Vector Profile",
          llm_model: "text-embedding-3-large",
          access_key: "vec_key",
          temperature: 0.0,
          base_uri: "https://api.openai.com",
          max_tokens: 0,
          llm_type: RedmineAiHelper::LlmProvider::LLM_OPENAI,
        )
      end

      teardown do
        @setting.update_columns(use_vector_model_profile: false, vector_model_profile_id: nil)
        @vector_profile.destroy if @vector_profile.persisted?
      end

      should "return normal provider when use_vector_model_profile is false" do
        @setting.update_columns(use_vector_model_profile: false, vector_model_profile_id: nil)
        normal_provider = @llm_provider.get_llm_provider
        vector_provider = @llm_provider.get_vector_llm_provider
        assert_equal normal_provider.class, vector_provider.class
        assert_equal normal_provider.model_name, vector_provider.model_name
      end

      should "return vector profile provider when use_vector_model_profile is true and profile exists" do
        @setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: @vector_profile.id)
        provider = @llm_provider.get_vector_llm_provider
        assert_not_nil provider
        assert_instance_of RedmineAiHelper::LlmClient::OpenAiProvider, provider
        assert_equal @vector_profile.llm_model, provider.model_name
      end

      should "fallback to normal provider when use_vector_model_profile is true but profile_id is blank" do
        @setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: nil)
        normal_provider = @llm_provider.get_llm_provider
        vector_provider = @llm_provider.get_vector_llm_provider
        assert_equal normal_provider.class, vector_provider.class
        assert_equal normal_provider.model_name, vector_provider.model_name
      end

      should "raise ActiveRecord::RecordNotFound when referenced profile is deleted" do
        @setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: 999999)
        assert_raises(ActiveRecord::RecordNotFound) do
          @llm_provider.get_vector_llm_provider
        end
      end
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
