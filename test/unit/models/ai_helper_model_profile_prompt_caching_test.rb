require File.expand_path("../../../test_helper", __FILE__)

class AiHelperModelProfilePromptCachingTest < ActiveSupport::TestCase
  context "AiHelperModelProfile prompt_caching_enabled" do
    should "default to true for a new record" do
      assert_equal true, AiHelperModelProfile.new.prompt_caching_enabled
    end

    should "be a safe attribute" do
      assert_includes AiHelperModelProfile.new.safe_attribute_names, "prompt_caching_enabled"
    end
  end
end
