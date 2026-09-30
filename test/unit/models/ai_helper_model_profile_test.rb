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

    assert_predicate profile, :valid?, "Profile should be valid: #{profile.errors.full_messages}"
    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
  end

  def test_should_require_name
    profile = AiHelperModelProfile.new(@valid_attributes.except(:name))

    assert_not profile.valid?
    assert_predicate profile.errors[:name], :present?
  end

  # Temperature is optional (Issue #465): nil passes validation (FR-001)
  def test_should_allow_blank_temperature
    profile = AiHelperModelProfile.new(@valid_attributes.merge(temperature: nil))

    assert profile.valid?, "Profile without temperature should be valid: #{profile.errors.full_messages}"
  end

  # Empty string and whitespace-only input are saved as nil (FR-009)
  def test_should_save_blank_temperature_strings_as_nil
    [ "", "  " ].each_with_index do |input, index|
      profile = AiHelperModelProfile.create!(@valid_attributes.merge(
        name: "Test Blank Temp #{index}",
        temperature: input
      ))

      assert_nil profile.reload.temperature, "Input #{input.inspect} should be saved as nil"
    end
  end

  # 0 is a valid value and is distinct from nil (Edge Case)
  def test_should_save_zero_temperature_as_zero
    profile = AiHelperModelProfile.create!(@valid_attributes.merge(name: "Test Zero Temp", temperature: "0"))

    assert_in_delta(0.0, profile.reload.temperature)
    assert_not_nil profile.temperature
  end

  # New profiles start without a temperature (FR-011)
  def test_new_profile_has_nil_temperature_by_default
    assert_nil AiHelperModelProfile.new.temperature
  end

  # GPT-5 series models are fixed to 1.0 even when temperature is unset (FR-010)
  def test_should_set_temperature_to_1_for_gpt5_model_with_nil_temperature
    test_cases = [
      "gpt-5",
      "gpt-5-turbo",
      "GPT-5-MINI"
    ]

    test_cases.each_with_index do |model_name, index|
      profile = AiHelperModelProfile.new(@valid_attributes.merge(
        name: "Test GPT5 Nil Temp #{index}",
        llm_model: model_name,
        temperature: nil
      ))

      assert profile.save, "Profile should save: #{profile.errors.full_messages}"
      assert_in_delta(1.0, profile.temperature, 0.001, "Temperature not set to 1.0 for model: #{model_name}")
    end
  end

  # Non-numeric temperature is rejected (FR-002)
  def test_should_reject_non_numeric_temperature
    profile = AiHelperModelProfile.new(@valid_attributes.merge(temperature: "abc"))

    assert_not profile.valid?
    assert_predicate profile.errors[:temperature], :present?
  end

  def test_should_validate_temperature_numericality
    profile = AiHelperModelProfile.new(@valid_attributes.merge(temperature: -1.0))

    assert_not profile.valid?
    assert_predicate profile.errors[:temperature], :present?
  end

  def test_should_allow_valid_http_proxy
    profile = AiHelperModelProfile.new(@valid_attributes.merge(http_proxy: "http://proxy.example.com:8080"))

    assert profile.valid?, "Profile with valid http_proxy should be valid: #{profile.errors.full_messages}"
  end

  def test_should_reject_invalid_http_proxy
    profile = AiHelperModelProfile.new(@valid_attributes.merge(http_proxy: "invalid-proxy"))

    assert_not profile.valid?
    assert_predicate profile.errors[:http_proxy], :present?
  end

  # GPT-5 temperature handling tests
  def test_should_set_temperature_to_1_for_exact_gpt5_model
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: "gpt-5",
      temperature: 0.5
    ))

    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
    assert_in_delta(1.0, profile.temperature)
  end

  def test_should_set_temperature_to_1_for_gpt5_model_case_insensitive
    profile = AiHelperModelProfile.new(@valid_attributes.merge(
      llm_model: "GPT-5",
      temperature: 0.3
    ))

    assert profile.save, "Profile should save: #{profile.errors.full_messages}"
    assert_in_delta(1.0, profile.temperature)
  end

  def test_should_set_temperature_to_1_for_gpt5_variants_without_chat
    test_cases = [
      "gpt-5-turbo",
      "GPT-5-TURBO",
      "gpt-5-preview",
      "gpt-5-advanced"
    ]

    test_cases.each_with_index do |model_name, index|
      profile = AiHelperModelProfile.new(@valid_attributes.merge(
        name: "Test GPT5 Variant #{index} #{model_name}",
        llm_model: model_name,
        temperature: 0.8
      ))

      assert profile.save, "Failed to save profile for model: #{model_name} - #{profile.errors.full_messages}"
      assert_in_delta(1.0, profile.temperature, 0.001, "Temperature not set to 1.0 for model: #{model_name}")
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
    assert_predicate profile.errors[:llm_model], :present?, "Model name error should be present"
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
    assert_predicate profile.errors[:llm_model], :present?
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
    assert_in_delta(1.0, profile.temperature)

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

    assert_in_delta(0.7, profile.temperature)

    # Update to GPT-5 model - temperature should be set to 1.0
    profile.update!(llm_model: "gpt-5", temperature: 0.3)

    assert_in_delta(1.0, profile.temperature)

    # Update back to non-GPT5 model with different temperature - should preserve it
    profile.update!(llm_model: "gpt-4", temperature: 0.9)

    assert_in_delta(0.9, profile.temperature)
  end
end
