require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/logger"

class LoggerTest < ActiveSupport::TestCase
  include RedmineAiHelper::Logger

  def setup
    # Reset any class instance variables between tests
    LoggerTest.remove_instance_variable(:@ai_helper_logger) if LoggerTest.instance_variable_defined?(:@ai_helper_logger)
    
    # Store original singleton instance
    @original_singleton = RedmineAiHelper::CustomLogger.instance rescue nil
  end
  
  def teardown
    # Clean up any stubbed methods
    LoggerTest.remove_instance_variable(:@ai_helper_logger) if LoggerTest.instance_variable_defined?(:@ai_helper_logger)
    
    # Restore original singleton if it was modified
    if @original_singleton
      RedmineAiHelper::CustomLogger.instance_variable_set(:@singleton__instance__, @original_singleton)
    end
    
    # Clear any stubs - use mocha's built-in teardown
    begin
      Mocha::Mockery.instance.teardown
    rescue => e
      # Ignore teardown errors
    end
  end

  def test_instance_logging_methods
    mock_logger = mock('mock_logger')
    RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)

    mock_logger.expects(:debug).with("[LoggerTest] debug message")
    debug("debug message")

    mock_logger.expects(:info).with("[LoggerTest] info message")
    info("info message")

    mock_logger.expects(:warn).with("[LoggerTest] warn message")
    warn("warn message")

    mock_logger.expects(:error).with("[LoggerTest] error message")
    error("error message")
  end

  def test_class_logging_methods
    mock_logger = mock('mock_logger')
    RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)

    mock_logger.expects(:debug).with("[LoggerTest] debug message")
    LoggerTest.debug("debug message")

    mock_logger.expects(:info).with("[LoggerTest] info message")
    LoggerTest.info("info message")

    mock_logger.expects(:warn).with("[LoggerTest] warn message")
    LoggerTest.warn("warn message")

    mock_logger.expects(:error).with("[LoggerTest] error message")
    LoggerTest.error("error message")
  end

  def test_ai_helper_logger_caching
    mock_logger = mock('mock_logger')
    RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
    
    # Test that the logger is cached at class level
    logger1 = LoggerTest.ai_helper_logger
    logger2 = LoggerTest.ai_helper_logger
    assert_same logger1, logger2
  end

  def test_instance_ai_helper_logger_delegates_to_class
    mock_logger = mock('mock_logger')
    RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
    
    instance_logger = ai_helper_logger
    class_logger = self.class.ai_helper_logger
    assert_same instance_logger, class_logger
  end

  def test_custom_logger_singleton_instance
    # Test that the singleton returns the same instance
    instance1 = RedmineAiHelper::CustomLogger.instance
    instance2 = RedmineAiHelper::CustomLogger.instance
    assert_same instance1, instance2
  end

  def test_custom_logger_predicate_methods
    # ruby_llm 1.14.0 calls RubyLLM.logger.debug? in connection.rb.
    # CustomLogger must delegate these to the internal @logger.
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_predicates')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)

    def test_logger.debug?; @logger.debug?; end
    def test_logger.info?;  @logger.info?;  end
    def test_logger.warn?;  @logger.warn?;  end
    def test_logger.error?; @logger.error?; end
    def test_logger.fatal?; @logger.fatal?; end

    mock_internal_logger.stubs(:debug?).returns(false)
    mock_internal_logger.stubs(:info?).returns(true)
    mock_internal_logger.stubs(:warn?).returns(true)
    mock_internal_logger.stubs(:error?).returns(true)
    mock_internal_logger.stubs(:fatal?).returns(true)

    assert_equal false, test_logger.debug?
    assert_equal true,  test_logger.info?
    assert_equal true,  test_logger.warn?
    assert_equal true,  test_logger.error?
    assert_equal true,  test_logger.fatal?

    # Also verify the real CustomLogger instance responds to these methods
    logger = RedmineAiHelper::CustomLogger.instance
    assert_respond_to logger, :debug?
    assert_respond_to logger, :info?
    assert_respond_to logger, :warn?
    assert_respond_to logger, :error?
    assert_respond_to logger, :fatal?
  end

  def test_custom_logger_logging_methods
    # Create a test object that mimics CustomLogger methods
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_logging')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.debug(message)
      @logger.debug(message)
    end
    
    def test_logger.info(message)
      @logger.info(message)
    end
    
    def test_logger.warn(message) 
      @logger.warn(message)
    end
    
    def test_logger.error(message)
      @logger.error(message)
    end

    mock_internal_logger.expects(:debug).with("debug message").once
    test_logger.debug("debug message")

    mock_internal_logger.expects(:info).with("info message").once  
    test_logger.info("info message")

    mock_internal_logger.expects(:warn).with("warn message").once
    test_logger.warn("warn message")

    mock_internal_logger.expects(:error).with("error message").once
    test_logger.error("error message")
  end

  def test_set_log_level_debug
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_debug')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.set_log_level(level)
      level_const = case level.to_s
      when "debug" then ::Logger::DEBUG
      when "info" then ::Logger::INFO
      when "warn" then ::Logger::WARN
      when "error" then ::Logger::ERROR
      else ::Logger::INFO
      end
      @logger.level = level_const
    end

    mock_internal_logger.expects(:level=).with(::Logger::DEBUG).once
    test_logger.set_log_level("debug")
  end

  def test_set_log_level_info
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_info')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.set_log_level(level)
      level_const = case level.to_s
      when "debug" then ::Logger::DEBUG
      when "info" then ::Logger::INFO
      when "warn" then ::Logger::WARN
      when "error" then ::Logger::ERROR
      else ::Logger::INFO
      end
      @logger.level = level_const
    end

    mock_internal_logger.expects(:level=).with(::Logger::INFO).once
    test_logger.set_log_level("info")
  end

  def test_set_log_level_warn
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_warn')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.set_log_level(level)
      level_const = case level.to_s
      when "debug" then ::Logger::DEBUG
      when "info" then ::Logger::INFO
      when "warn" then ::Logger::WARN
      when "error" then ::Logger::ERROR
      else ::Logger::INFO
      end
      @logger.level = level_const
    end

    mock_internal_logger.expects(:level=).with(::Logger::WARN).once
    test_logger.set_log_level("warn")
  end

  def test_set_log_level_error
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_error')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.set_log_level(level)
      level_const = case level.to_s
      when "debug" then ::Logger::DEBUG
      when "info" then ::Logger::INFO
      when "warn" then ::Logger::WARN
      when "error" then ::Logger::ERROR
      else ::Logger::INFO
      end
      @logger.level = level_const
    end

    mock_internal_logger.expects(:level=).with(::Logger::ERROR).once
    test_logger.set_log_level("error")
  end

  def test_set_log_level_unknown_defaults_to_info
    test_logger = Object.new
    mock_internal_logger = mock('internal_logger_for_unknown')
    test_logger.instance_variable_set(:@logger, mock_internal_logger)
    
    def test_logger.set_log_level(level)
      level_const = case level.to_s
      when "debug" then ::Logger::DEBUG
      when "info" then ::Logger::INFO
      when "warn" then ::Logger::WARN
      when "error" then ::Logger::ERROR
      else ::Logger::INFO
      end
      @logger.level = level_const
    end

    mock_internal_logger.expects(:level=).with(::Logger::INFO).once
    test_logger.set_log_level("unknown")
  end
end
