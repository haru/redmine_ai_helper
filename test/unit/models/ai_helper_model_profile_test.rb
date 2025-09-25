require_relative "../../test_helper"

class AiHelperModelProfileTest < ActiveSupport::TestCase

  def setup
    # Clean up any existing test data
    AiHelperModelProfile.where("name LIKE ?", "Test%").delete_all

    @valid_attributes = {
      name: "Test Profile",
      llm_type: "OpenAI",
      access_key: "test-key",
      llm_model: "gpt-4",
      temperature: 0.7
    }
  end

  def teardown
    # Clean up test data after each test
    AiHelperModelProfile.where("name LIKE ?", "Test%").delete_all
  end

  def test_should_create_valid_model_profile
    profile = AiHelperModelProfile.new(@valid_attributes)
    assert profile.valid?, "Profile should be valid: #{profile.errors.full_messages}"
    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
  end

  def test_should_require_name
    profile = AiHelperModelProfile.new(@valid_attributes.except(:name))
    assert_not profile.valid?
    assert profile.errors[:name].present?
  end

  def test_should_require_temperature
    profile = AiHelperModelProfile.new(@valid_attributes.merge(temperature: nil))
    assert_not profile.valid?, "Profile without temperature should not be valid"
    assert profile.errors[:temperature].present?, "Temperature error should be present: #{profile.errors.full_messages}"
  end

  def test_should_validate_temperature_numericality
    profile = AiHelperModelProfile.new(@valid_attributes.merge(temperature: -1.0))
    assert_not profile.valid?
    assert profile.errors[:temperature].present?
  end

  # GPT-5 temperature handling tests
  def test_should_set_temperature_to_1_for_exact_gpt5_model
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: "gpt-5",
      temperature: 0.5
    ))
    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
    assert_equal 1.0, profile.temperature
  end

  def test_should_set_temperature_to_1_for_gpt5_model_case_insensitive
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: "GPT-5",
      temperature: 0.3
    ))
    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
    assert_equal 1.0, profile.temperature
  end

  def test_should_set_temperature_to_1_for_gpt5_variants_without_chat
    test_cases = [
      "gpt-5-turbo",
      "GPT-5-TURBO",
      "gpt-5-preview",
      "gpt-5-advanced"
    ]

    test_cases.each do |model_name|
      profile = AiHelperModelProfile.new(@valid_attributes.merge(
        name: "Test #{model_name}",
        llm_model: model_name,
        temperature: 0.8
      ))
      assert profile.save, "Failed to save profile for model: #{model_name}"
      assert_equal 1.0, profile.temperature, "Temperature not set to 1.0 for model: #{model_name}"
    end
  end

  def test_should_not_modify_temperature_for_gpt5_chat_models
    test_cases = [
      "gpt-5-chat",
      "gpt-5-turbo-chat",
      "GPT-5-Chat-Preview"
    ]

    test_cases.each do |model_name|
      original_temp = 0.7
      profile = AiHelperModelProfile.new(@valid_attributes.merge(
        name: "Test #{model_name}",
        llm_model: model_name,
        temperature: original_temp
      ))
      assert profile.save, "Failed to save profile for model: #{model_name}"
      assert_equal original_temp, profile.temperature, "Temperature was modified for chat model: #{model_name}"
    end
  end

  def test_should_not_modify_temperature_for_non_gpt5_models
    test_cases = [
      "gpt-4",
      "gpt-4-turbo",
      "gpt-3.5-turbo",
      "claude-3",
      "gemini-pro",
      "gpt5-custom" # doesn't start with "gpt-5"
    ]

    test_cases.each do |model_name|
      original_temp = 0.5
      profile = AiHelperModelProfile.new(@valid_attributes.merge(
        name: "Test #{model_name}",
        llm_model: model_name,
        temperature: original_temp
      ))
      assert profile.save, "Failed to save profile for model: #{model_name}"
      assert_equal original_temp, profile.temperature, "Temperature was modified for non-GPT5 model: #{model_name}"
    end
  end

  def test_should_not_modify_temperature_for_empty_model_name
    original_temp = 0.5
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      name: "Test Empty Model",
      llm_model: "",
      temperature: original_temp
    ))
    # Empty model name should not be valid due to presence requirement
    assert_not profile.valid?, "Profile with empty model name should not be valid"
    assert profile.errors[:llm_model].present?, "Model name error should be present"
    # Temperature should still not be modified even with invalid model
    assert_equal original_temp, profile.temperature, "Temperature was modified for empty model name"
  end

  def test_should_handle_blank_model_name
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: nil,
      temperature: 0.8
    ))
    # Should fail validation due to presence requirement for llm_model
    assert_not profile.valid?
    assert profile.errors[:llm_model].present?
  end

  def test_gpt5_model_requiring_fixed_temperature_detection
    profile = AiHelperModelProfile.new(@valid_attributes)

    # Test exact match
    profile.llm_model = "gpt-5"
    assert profile.send(:gpt5_model_requiring_fixed_temperature?)

    # Test case insensitive
    profile.llm_model = "GPT-5"
    assert profile.send(:gpt5_model_requiring_fixed_temperature?)

    # Test variants without chat
    profile.llm_model = "gpt-5-turbo"
    assert profile.send(:gpt5_model_requiring_fixed_temperature?)

    # Test variants with chat (should not match)
    profile.llm_model = "gpt-5-chat"
    assert_not profile.send(:gpt5_model_requiring_fixed_temperature?)

    # Test non-GPT5 models
    profile.llm_model = "gpt-4"
    assert_not profile.send(:gpt5_model_requiring_fixed_temperature?)

    # Test blank model
    profile.llm_model = nil
    assert_not profile.send(:gpt5_model_requiring_fixed_temperature?)
  end

  def test_should_preserve_other_attributes_when_modifying_temperature
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: "gpt-5",
      temperature: 0.5,
      max_tokens: 1000
    ))
    assert profile.save, "Profile should save: #{profile.errors.full_messages}"

    # Temperature should be modified
    assert_equal 1.0, profile.temperature

    # Other attributes should be preserved
    assert_equal "Test Profile", profile.name
    assert_equal "gpt-5", profile.llm_model
    assert_equal 1000, profile.max_tokens
  end

  def test_should_work_with_model_updates
    # Create a profile with non-GPT5 model
    profile = AiHelperModelProfile.create!(@valid_attributes.merge(
      name: "Test Update Profile",
      llm_model: "gpt-4",
      temperature: 0.7
    ))
    assert_equal 0.7, profile.temperature

    # Update to GPT-5 model - temperature should be set to 1.0
    profile.update!(llm_model: "gpt-5", temperature: 0.3)
    assert_equal 1.0, profile.temperature

    # Update back to non-GPT5 model with different temperature - should preserve it
    profile.update!(llm_model: "gpt-4", temperature: 0.9)
    assert_equal 0.9, profile.temperature
  end
end
