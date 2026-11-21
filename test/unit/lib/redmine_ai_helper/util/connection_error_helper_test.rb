# frozen_string_literal: true

require File.expand_path("../../../../test_helper", __dir__)

class RedmineAiHelper::Util::ConnectionErrorHelperTest < ActiveSupport::TestCase
  include RedmineAiHelper::TestSupport::ConnectionErrors

  context "timeout?" do
    should "be true for a read timeout" do
      assert RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(build_connection_error(:read_timeout))
    end

    should "be true for a connect timeout" do
      assert RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(build_connection_error(:connect_timeout))
    end

    should "be false for a refused connection" do
      assert_not RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(build_connection_error(:refused))
    end

    should "be false for an SSL failure" do
      assert_not RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(build_connection_error(:ssl_error))
    end

    should "be false for a RubyLLM::Error that is not a ConnectionError" do
      assert_not RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(RubyLLM::ServerError.new("boom"))
    end

    should "be false for a ConnectionError without a cause" do
      assert_not RedmineAiHelper::Util::ConnectionErrorHelper.timeout?(RubyLLM::ConnectionError.new("x"))
    end
  end

  context "describe" do
    should "name the error class, the message and the class of the cause" do
      text = RedmineAiHelper::Util::ConnectionErrorHelper.describe(build_connection_error(:refused))
      assert_includes text, "RubyLLM::ConnectionError"
      assert_includes text, "Faraday::ConnectionFailed"
    end

    should "name the wrapped exception of a Faraday::ConnectionFailed cause" do
      text = RedmineAiHelper::Util::ConnectionErrorHelper.describe(build_connection_error(:refused))
      assert_includes text, "Errno::ECONNREFUSED"
    end

    should "describe an error without a cause by class and message only" do
      text = RedmineAiHelper::Util::ConnectionErrorHelper.describe(RubyLLM::ServerError.new("boom"))
      assert_equal "RubyLLM::ServerError: boom", text
    end
  end
end
