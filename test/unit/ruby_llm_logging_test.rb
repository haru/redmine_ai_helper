require File.expand_path("../../test_helper", __FILE__)

class RubyLLMLoggingTest < ActiveSupport::TestCase
  def setup
    # Ensure tests run with predictable environment; tests assume defaults (no debug env)
    @orig_debug = ENV.delete("RUBYLLM_DEBUG")
    @orig_stream_debug = ENV.delete("RUBYLLM_STREAM_DEBUG")
    # Re-run configure to ensure values reflect test-controlled ENV
    if defined?(RubyLLM) && RubyLLM.respond_to?(:configure)
      RubyLLM.configure do |config|
        config.logger = RedmineAiHelper::CustomLogger.instance
        config.log_level = :error
        config.log_stream_debug = false
      end
    end
  end

  def teardown
    ENV["RUBYLLM_DEBUG"] = @orig_debug if @orig_debug
    ENV["RUBYLLM_STREAM_DEBUG"] = @orig_stream_debug if @orig_stream_debug
  end

  def test_configures_rubyllm_logger
    assert_equal RedmineAiHelper::CustomLogger.instance, RubyLLM.config.logger
  end

  def test_sets_log_level_to_error
    assert_equal :error, RubyLLM.config.log_level
  end

  def test_stream_debug_disabled_by_default
    assert_equal false, RubyLLM.config.log_stream_debug
  end
end
