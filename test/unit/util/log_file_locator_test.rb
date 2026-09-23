require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/log_file_locator"

class RedmineAiHelper::Util::LogFileLocatorTest < ActiveSupport::TestCase
  Locator = RedmineAiHelper::Util::LogFileLocator

  setup do
    @original_logger = Rails.logger
    @original_stdout_env = ENV.fetch("RAILS_LOG_TO_STDOUT", nil)
    @tmpdir = Dir.mktmpdir
    @opened_files = []
  end

  teardown do
    Rails.logger = @original_logger
    if @original_stdout_env.nil?
      ENV.delete("RAILS_LOG_TO_STDOUT")
    else
      ENV["RAILS_LOG_TO_STDOUT"] = @original_stdout_env
    end
    @opened_files.each(&:close)
    FileUtils.remove_entry(@tmpdir)
  end

  # Opens a file in the temporary directory the way Rails' default_log_file does.
  def open_log_file(name = "production.log")
    file = File.open(File.join(@tmpdir, name), "a")
    @opened_files << file
    file
  end

  def broadcast(*loggers)
    ActiveSupport::BroadcastLogger.new(*loggers)
  end

  context "constants" do
    should "list the supported log types" do
      assert_equal %w[redmine ai_helper], Locator::LOG_TYPES
      assert_equal "redmine", Locator::DEFAULT_LOG_TYPE
    end
  end

  context "unknown log types" do
    should "raise ArgumentError without touching any logger" do
      [ "nginx", "../../etc/passwd", "/var/log/nginx/error.log", nil ].each do |log_type|
        assert_raises(ArgumentError) { Locator.resolve(log_type) }
      end
    end
  end

  context "redmine" do
    should "resolve the path of a logger opened with a File object" do
      file = open_log_file
      Rails.logger = broadcast(ActiveSupport::Logger.new(file))

      assert_equal file.path, Locator.resolve("redmine")
    end

    should "resolve the path of a logger opened with a path string" do
      path = File.join(@tmpdir, "string.log")
      logger = ActiveSupport::Logger.new(path)
      Rails.logger = broadcast(logger)

      assert_equal path, Locator.resolve("redmine")
    ensure
      logger&.close
    end

    should "resolve a plain logger that is not a BroadcastLogger" do
      file = open_log_file
      Rails.logger = ActiveSupport::Logger.new(file)

      assert_equal file.path, Locator.resolve("redmine")
    end

    should "prefer the file broadcast when a StringIO broadcast is also present" do
      file = open_log_file
      Rails.logger = broadcast(ActiveSupport::Logger.new(StringIO.new), ActiveSupport::Logger.new(file))

      assert_equal file.path, Locator.resolve("redmine")
    end

    should "be unavailable when the logger writes to a device" do
      # Logger ignores File::NULL entirely, so another device is used.
      skip "/dev/zero is not available" unless File.exist?("/dev/zero")
      logger = ActiveSupport::Logger.new("/dev/zero")
      Rails.logger = broadcast(logger)

      error = assert_raises(Locator::UnavailableError) { Locator.resolve("redmine") }
      assert_includes error.message, "device or a pipe"
      assert_not_includes error.message, "/dev/zero"
    ensure
      logger&.close
    end

    should "be unavailable when only non-file loggers are present" do
      ENV.delete("RAILS_LOG_TO_STDOUT")
      [ StringIO.new, $stdout, $stderr ].each do |io|
        Rails.logger = broadcast(ActiveSupport::Logger.new(io))

        error = assert_raises(Locator::UnavailableError) { Locator.resolve("redmine") }
        assert_match(/does not write to a file/, error.message)
        assert_not_includes error.message, @tmpdir
      end
    end

    should "mention RAILS_LOG_TO_STDOUT when it is set" do
      ENV["RAILS_LOG_TO_STDOUT"] = "1"
      Rails.logger = broadcast(ActiveSupport::Logger.new($stdout))

      error = assert_raises(Locator::UnavailableError) { Locator.resolve("redmine") }
      assert_includes error.message, "RAILS_LOG_TO_STDOUT"
      assert_not_includes error.message, @tmpdir
    end

    should "be resolved regardless of the ai_helper log" do
      file = open_log_file
      Rails.logger = broadcast(ActiveSupport::Logger.new(file))
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({})

      assert_equal file.path, Locator.resolve("redmine")
    end
  end

  context "ai_helper" do
    should "resolve the file configured in config.yml" do
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({ logger: { file: "custom_ai.log" } })

      assert_equal Rails.root.join("log/custom_ai.log").to_s, Locator.resolve("ai_helper")
    end

    should "resolve the default file when the logger section has no file" do
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({ logger: { level: "debug" } })

      assert_equal Rails.root.join("log/ai_helper.log").to_s, Locator.resolve("ai_helper")
    end

    should "be unavailable without a logger section" do
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({})

      error = assert_raises(Locator::UnavailableError) { Locator.resolve("ai_helper") }
      assert_includes error.message, "config/ai_helper/config.yml has no logger section"
      assert_not_includes error.message, Rails.root.to_s
    end

    should "be unavailable without leaking the path when config.yml cannot be parsed" do
      error_with_path = Psych::SyntaxError.new(Rails.root.join("config/ai_helper/config.yml").to_s, 1, 1, 0, "bad", "context")
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).raises(error_with_path)

      error = assert_raises(Locator::UnavailableError) { Locator.resolve("ai_helper") }
      assert_includes error.message, "could not be read"
      assert_not_includes error.message, Rails.root.to_s
    end

    should "be unavailable when config.yml is empty" do
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).raises(NoMethodError, "undefined method 'deep_symbolize_keys' for false")

      assert_raises(Locator::UnavailableError) { Locator.resolve("ai_helper") }
    end

    should "be unavailable when the logger section is not a mapping" do
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({ logger: "debug" })

      error = assert_raises(Locator::UnavailableError) { Locator.resolve("ai_helper") }
      assert_includes error.message, "logger section is invalid"
    end

    should "be resolved even when the redmine log is unavailable" do
      Rails.logger = broadcast(ActiveSupport::Logger.new(StringIO.new))
      RedmineAiHelper::Util::ConfigFile.stubs(:load_config).returns({ logger: {} })

      assert_equal Rails.root.join("log/ai_helper.log").to_s, Locator.resolve("ai_helper")
    end
  end
end
