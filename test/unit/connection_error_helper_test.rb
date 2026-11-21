# frozen_string_literal: true

require File.expand_path("../test_helper", __dir__)

# Pins the shape of the errors built by the test helper to what RubyLLM 2.2's
# ErrorMiddleware produces, because every timeout test relies on it.
class ConnectionErrorHelperTest < ActiveSupport::TestCase
  include RedmineAiHelper::TestSupport::ConnectionErrors

  context "build_connection_error" do
    should "build a read timeout caused by Faraday::TimeoutError" do
      error = build_connection_error(:read_timeout)
      assert_kind_of RubyLLM::ConnectionError, error
      assert_kind_of Faraday::TimeoutError, error.cause
      assert error.timeout?
    end

    should "build a connect timeout wrapping Net::OpenTimeout" do
      error = build_connection_error(:connect_timeout)
      assert_kind_of RubyLLM::ConnectionError, error
      assert_kind_of Faraday::ConnectionFailed, error.cause
      assert_kind_of Net::OpenTimeout, error.cause.wrapped_exception
      assert error.timeout?
    end

    should "build a refused connection that is not a timeout" do
      error = build_connection_error(:refused)
      assert_kind_of RubyLLM::ConnectionError, error
      assert_kind_of Faraday::ConnectionFailed, error.cause
      assert_kind_of Errno::ECONNREFUSED, error.cause.wrapped_exception
      assert_not error.timeout?
    end

    should "build an SSL failure that is not a timeout" do
      error = build_connection_error(:ssl_error)
      assert_kind_of RubyLLM::ConnectionError, error
      assert_kind_of Faraday::SSLError, error.cause
      assert_not error.timeout?
    end

    should "expose every supported kind" do
      assert_equal %i[read_timeout connect_timeout refused ssl_error], RedmineAiHelper::TestSupport::ConnectionErrors::KINDS
    end

    should "raise ArgumentError for an unknown kind" do
      assert_raises(ArgumentError) { build_connection_error(:bogus) }
    end

    should "report a ConnectionError without a cause as not a timeout" do
      assert_not RubyLLM::ConnectionError.new("x").timeout?
    end
  end
end
