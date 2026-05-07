require File.expand_path("../../test_helper", __FILE__)


class ToolResponseTest < ActiveSupport::TestCase
  def test_initialize_with_success_status
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value")

    assert_equal RedmineAiHelper::ToolResponse::STATUS_SUCCESS, response.status
    assert_equal "Test value", response.value
    assert_nil response.error
  end

  def test_initialize_with_error_status
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_ERROR, error: "Test error")

    assert_equal RedmineAiHelper::ToolResponse::STATUS_ERROR, response.status
    assert_nil response.value
    assert_equal "Test error", response.error
  end

  def test_to_json
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value")
    expected_json = { status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value", error: nil }.to_json

    assert_equal expected_json, response.to_json
  end

  def test_to_hash
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value")
    expected_hash = { status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value", error: nil }

    assert_equal expected_hash, response.to_hash
  end

  def test_to_h
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value")
    expected_hash = { status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value", error: nil }

    assert_equal expected_hash, response.to_h
  end

  def test_to_s
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value")
    expected_string = { status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS, value: "Test value", error: nil }.to_s

    assert_equal expected_string, response.to_s
  end

  def test_is_success?
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_SUCCESS)

    assert_predicate response, :is_success?
  end

  def test_is_error?
    response = RedmineAiHelper::ToolResponse.new(status: RedmineAiHelper::ToolResponse::STATUS_ERROR)

    assert_predicate response, :is_error?
  end

  def test_create_error
    response = RedmineAiHelper::ToolResponse.create_error("Test error")

    assert_equal RedmineAiHelper::ToolResponse::STATUS_ERROR, response.status
    assert_equal "Test error", response.error
    assert_nil response.value
  end

  def test_create_success
    response = RedmineAiHelper::ToolResponse.create_success("Test value")

    assert_equal RedmineAiHelper::ToolResponse::STATUS_SUCCESS, response.status
    assert_equal "Test value", response.value
    assert_nil response.error
  end
end
