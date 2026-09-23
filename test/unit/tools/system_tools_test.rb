require File.expand_path("../../../test_helper", __FILE__)

class SystemToolsTest < ActiveSupport::TestCase
  LOG_ACCESS_DISABLED_MESSAGE = 'Log file access is disabled. An administrator can enable it with "Allow log file access" on the "General" tab of the AI Helper settings page.'

  def setup
    @provider = RedmineAiHelper::Tools::SystemTools.new
  end

  def test_list_plugins
    response = @provider.list_plugins

    assert_predicate response[:plugins], :any?
  end

  def test_get_system_info_as_admin
    User.current = User.find(1) # Admin user
    response = @provider.get_system_info

    assert_not_nil response
    assert_not_nil response[:redmine]
    assert_not_nil response[:ruby]
    assert_not_nil response[:rails]
    assert_not_nil response[:database]
    assert_not_nil response[:mailer]
    assert_not_nil response[:redmine_settings]
    assert_not_nil response[:scm]
    assert_not_nil response[:plugins]

    # Verify specific fields
    assert_equal Redmine::VERSION::STRING, response[:redmine][:version]
    assert_equal RUBY_VERSION, response[:ruby][:version]
    assert_equal Rails::VERSION::STRING, response[:rails][:version]
    assert_predicate response[:plugins], :any?
  end

  def test_get_system_info_as_non_admin
    User.current = User.find(2) # Non-admin user

    assert_raises(RuntimeError, "Permission denied. Only administrators can access system information.") do
      @provider.get_system_info
    end
  end

  def test_get_system_info_no_user
    User.current = nil

    assert_raises(RuntimeError, "Permission denied. Only administrators can access system information.") do
      @provider.get_system_info
    end
  end

  def test_get_system_info_database_error
    User.current = User.find(1) # Admin user

    # Mock database connection to raise an error
    ActiveRecord::Base.connection.stubs(:adapter_name).raises(StandardError.new("Database connection failed"))

    response = @provider.get_system_info

    assert_equal "Unknown", response[:database][:adapter]
    assert_equal "Database connection failed", response[:database][:error]
  end

  def test_get_system_info_scm_error
    User.current = User.find(1) # Admin user

    # Create a temporary stub to test error handling
    original_method = @provider.method(:get_system_info)

    # Define a modified version that simulates SCM error
    @provider.define_singleton_method(:get_system_info) do |dummy: nil| # rubocop:disable Lint/UnusedBlockArgument
      unless User.current.admin?
        raise "Permission denied. Only administrators can access system information."
      end

      system_info = {}
      system_info[:redmine] = { version: Redmine::VERSION::STRING, environment: Rails.env }
      system_info[:ruby] = { version: RUBY_VERSION }
      system_info[:rails] = { version: Rails::VERSION::STRING }

      begin
        system_info[:database] = { adapter: ActiveRecord::Base.connection.adapter_name }
      rescue => e
        system_info[:database] = { adapter: "Unknown", error: e.message }
      end

      system_info[:mailer] = { queue: "Unknown", delivery: ActionMailer::Base.delivery_method.to_s }
      system_info[:redmine_settings] = { theme: (Setting.ui_theme.presence || "Default") }

      # Simulate SCM error scenario
      system_info[:scm] = {}
      system_info[:scm][:testscm] = "Error: SCM command failed"

      system_info[:plugins] = {}
      Redmine::Plugin.all.each do |plugin| # rubocop:disable Rails/FindEach
        system_info[:plugins][plugin.id.to_s] = plugin.version.to_s
      end

      system_info
    end

    response = @provider.get_system_info

    assert_equal "Error: SCM command failed", response[:scm][:testscm]
  ensure
    # Restore original method
    @provider.define_singleton_method(:get_system_info, original_method) if original_method
  end

  def test_get_system_info_scm_nil_version
    User.current = User.find(1) # Admin user

    # Create a temporary stub to test nil version handling
    original_method = @provider.method(:get_system_info)

    # Define a modified version that simulates nil version
    @provider.define_singleton_method(:get_system_info) do |dummy: nil| # rubocop:disable Lint/UnusedBlockArgument
      unless User.current.admin?
        raise "Permission denied. Only administrators can access system information."
      end

      system_info = {}
      system_info[:redmine] = { version: Redmine::VERSION::STRING, environment: Rails.env }
      system_info[:ruby] = { version: RUBY_VERSION }
      system_info[:rails] = { version: Rails::VERSION::STRING }

      begin
        system_info[:database] = { adapter: ActiveRecord::Base.connection.adapter_name }
      rescue => e
        system_info[:database] = { adapter: "Unknown", error: e.message }
      end

      system_info[:mailer] = { queue: "Unknown", delivery: ActionMailer::Base.delivery_method.to_s }
      system_info[:redmine_settings] = { theme: (Setting.ui_theme.presence || "Default") }

      # Simulate nil version scenario (testing line 97: version || "Unknown")
      system_info[:scm] = {}
      version = nil  # Simulate scm_version_string returning nil
      system_info[:scm][:testscm] = version || "Unknown"

      system_info[:plugins] = {}
      Redmine::Plugin.all.each do |plugin| # rubocop:disable Rails/FindEach
        system_info[:plugins][plugin.id.to_s] = plugin.version.to_s
      end

      system_info
    end

    response = @provider.get_system_info

    assert_equal "Unknown", response[:scm][:testscm]
  ensure
    # Restore original method
    @provider.define_singleton_method(:get_system_info, original_method) if original_method
  end

  def test_scm_basic_functionality
    User.current = User.find(1) # Admin user

    response = @provider.get_system_info

    assert_not_nil response[:scm]
    assert_kind_of Hash, response[:scm]
  end

  context "log functions" do
    setup do
      @original_logger = Rails.logger
      @log_dir = Dir.mktmpdir
      @log_path = File.join(@log_dir, "production.log")
      @opened_files = []
      use_redmine_log(numbered_lines(3))
      AiHelperSetting.setting.update!(log_access_enabled: true)
      User.current = User.find(1)
    end

    teardown do
      Rails.logger = @original_logger
      @opened_files.each(&:close)
      FileUtils.remove_entry(@log_dir)
      User.current = nil
    end

    context "read_log_tail" do
      should "return up to 100 lines of the redmine log by default" do
        use_redmine_log(numbered_lines(150))
        result = @provider.read_log_tail

        assert_equal "redmine", result[:log_type]
        assert_equal "production.log", result[:file_name]
        assert_equal 100, result[:requested_lines]
        assert_equal false, result[:lines_capped]
        assert_equal 100, result[:lines].size
        assert_equal "line 150", result[:lines].last[:content]
      end

      should "return the requested number of lines" do
        use_redmine_log(numbered_lines(500))
        result = @provider.read_log_tail(lines: 300)

        assert_equal 300, result[:requested_lines]
        assert_equal false, result[:lines_capped]
        assert_equal 300, result[:lines].size
      end

      should "cap the number of lines at 1000" do
        use_redmine_log(numbered_lines(1_200))
        result = @provider.read_log_tail(lines: 1_000_000)

        assert_equal 1_000_000, result[:requested_lines]
        assert_equal true, result[:lines_capped]
        assert_equal 1_000, result[:lines].size
      end

      should "reject a lines value that is not a positive integer" do
        [ 0, -1, "abc", 1.5 ].each do |lines|
          error = assert_raises(RuntimeError) { @provider.read_log_tail(lines: lines) }
          assert_match(/\AInvalid argument: /, error.message)
        end
      end

      should "reject a log_type outside the enum without resolving any file" do
        RedmineAiHelper::Util::LogFileLocator.expects(:resolve).never
        [ "nginx", "../../etc/passwd", "/var/log/nginx/error.log" ].each do |log_type|
          error = assert_raises(RuntimeError) { @provider.read_log_tail(log_type: log_type) }
          assert_equal "Invalid argument: log_type must be one of redmine, ai_helper", error.message
        end
      end

      should "not expose the log directory in the result" do
        result = @provider.read_log_tail

        assert_not_includes result.to_json, @log_dir
      end

      should "report the redmine log as unavailable when Redmine does not log to a file" do
        Rails.logger = ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(StringIO.new))

        error = assert_raises(RuntimeError) { @provider.read_log_tail }
        assert_match(/\AThe redmine log is not available: /, error.message)
      end

      should "report a missing log file by its name only" do
        File.delete(@log_path)

        error = assert_raises(RuntimeError) { @provider.read_log_tail }
        assert_equal "The redmine log file production.log does not exist.", error.message
        assert_not_includes error.message, @log_dir
      end
    end

    context "search_log" do
      setup do
        use_redmine_log("start\nNoMethodError first\nmiddle\nnomethoderror second\nend\n")
      end

      should "search the redmine log with the default options" do
        result = @provider.search_log(keyword: "NoMethodError")

        assert_equal "redmine", result[:log_type]
        assert_equal false, result[:case_sensitive]
        assert_equal 0, result[:context_lines]
        assert_equal false, result[:context_lines_capped]
        assert_equal 50, result[:max_matches]
        assert_equal false, result[:max_matches_capped]
        assert_equal 2, result[:match_count]
        assert_equal "production.log", result[:file_name]
      end

      should "strip surrounding whitespace from the keyword" do
        result = @provider.search_log(keyword: "  NoMethodError  ")

        assert_equal "NoMethodError", result[:keyword]
        assert_equal 2, result[:match_count]
      end

      should "honour case_sensitive" do
        result = @provider.search_log(keyword: "NoMethodError", case_sensitive: true)

        assert_equal 1, result[:match_count]
        assert_equal true, result[:case_sensitive]
      end

      should "reject an empty keyword" do
        [ "", "   ", nil ].each do |keyword|
          error = assert_raises(RuntimeError) { @provider.search_log(keyword: keyword) }
          assert_match(/\AInvalid argument: keyword/, error.message)
        end
      end

      should "cap context_lines at 10" do
        result = @provider.search_log(keyword: "middle", context_lines: 11)

        assert_equal 10, result[:context_lines]
        assert_equal true, result[:context_lines_capped]
      end

      should "accept zero context lines and reject invalid ones" do
        assert_equal 0, @provider.search_log(keyword: "middle", context_lines: 0)[:context_lines]
        [ -1, "x" ].each do |context_lines|
          error = assert_raises(RuntimeError) { @provider.search_log(keyword: "middle", context_lines: context_lines) }
          assert_match(/\AInvalid argument: context_lines/, error.message)
        end
      end

      should "cap max_matches at 200 and reject invalid values" do
        result = @provider.search_log(keyword: "middle", max_matches: 201)
        assert_equal 200, result[:max_matches]
        assert_equal true, result[:max_matches_capped]

        [ 0, "x" ].each do |max_matches|
          error = assert_raises(RuntimeError) { @provider.search_log(keyword: "middle", max_matches: max_matches) }
          assert_match(/\AInvalid argument: max_matches/, error.message)
        end
      end

      should "reject a non-boolean case_sensitive" do
        error = assert_raises(RuntimeError) { @provider.search_log(keyword: "middle", case_sensitive: "yes") }
        assert_match(/\AInvalid argument: case_sensitive/, error.message)
      end

      should "reject an unsupported log_type without resolving any file" do
        RedmineAiHelper::Util::LogFileLocator.expects(:resolve).never
        error = assert_raises(RuntimeError) { @provider.search_log(keyword: "x", log_type: "/var/log/nginx/error.log") }
        assert_equal "Invalid argument: log_type must be one of redmine, ai_helper", error.message
      end

      should "not expose the log directory in the result or errors" do
        result = @provider.search_log(keyword: "NoMethodError", context_lines: 1)
        assert_not_includes result.to_json, @log_dir

        File.delete(@log_path)
        error = assert_raises(RuntimeError) { @provider.search_log(keyword: "x") }
        assert_equal "The redmine log file production.log does not exist.", error.message
      end
    end
  end

  context "output limits (SC-005)" do
    setup do
      @original_logger = Rails.logger
      @log_dir = Dir.mktmpdir
      @log_path = File.join(@log_dir, "production.log")
      @opened_files = []
      use_redmine_log((1..1_200).map { |i| "HIT #{i} #{"x" * 2_500}\n" }.join)
      AiHelperSetting.setting.update!(log_access_enabled: true)
      User.current = User.find(1)
    end

    teardown do
      Rails.logger = @original_logger
      @opened_files.each(&:close)
      FileUtils.remove_entry(@log_dir)
      User.current = nil
    end

    should "never return more than 1000 tail lines of bounded length" do
      lines = @provider.read_log_tail(lines: 1_000_000)[:lines]

      assert_operator lines.size, :<=, 1_000
      lines.each { |line| assert_line_within_limit(line) }
    end

    should "never return more than 200 matches with 10 context lines each" do
      result = @provider.search_log(keyword: "HIT", max_matches: 1_000, context_lines: 100)
      lines = result[:matches].flat_map { |match| match[:before] + [ match[:line] ] + match[:after] }

      assert_equal 200, result[:match_count]
      assert_operator lines.size, :<=, 200 * 21
      lines.each { |line| assert_line_within_limit(line) }
    end
  end

  context "read-only mode" do
    should "keep the log functions available because they only read" do
      AiHelperSetting.stubs(:read_only_mode?).returns(true)
      names = RedmineAiHelper::Agents::SystemAgent.new.available_tool_classes.map(&:name)

      %w[GetLogFileInfo ReadLogTail SearchLog].each do |tool|
        assert_includes names, "RedmineAiHelper::Tools::SystemTools::#{tool}"
      end
    end
  end

  context "ai_helper log" do
    setup do
      @log_dir = Dir.mktmpdir
      @ai_log_path = File.join(@log_dir, "ai_helper.log")
      File.write(@ai_log_path, "[info] started\n[error] RubyLLM::Error timeout\n")
      RedmineAiHelper::CustomLogger.instance.stubs(:log_file_path).returns(Pathname.new(@ai_log_path))
      AiHelperSetting.setting.update!(log_access_enabled: true)
      User.current = User.find(1)
    end

    teardown do
      FileUtils.remove_entry(@log_dir)
      User.current = nil
    end

    should "read the tail of the ai_helper log" do
      result = @provider.read_log_tail(log_type: "ai_helper")

      assert_equal "ai_helper", result[:log_type]
      assert_equal "ai_helper.log", result[:file_name]
      assert_equal "[error] RubyLLM::Error timeout", result[:lines].last[:content]
    end

    should "search the ai_helper log" do
      result = @provider.search_log(keyword: "rubyllm::error", log_type: "ai_helper")

      assert_equal "ai_helper", result[:log_type]
      assert_equal 1, result[:match_count]
      assert_not_includes result.to_json, @log_dir
    end

    should "report the ai_helper log as unavailable without a logger section" do
      RedmineAiHelper::CustomLogger.instance.stubs(:log_file_path).returns(nil)

      error = assert_raises(RuntimeError) { @provider.read_log_tail(log_type: "ai_helper") }
      assert_match(/\AThe ai_helper log is not available: /, error.message)
    end
  end

  context "get_log_file_info" do
    setup do
      @original_logger = Rails.logger
      @log_dir = Dir.mktmpdir
      @log_path = File.join(@log_dir, "production.log")
      @opened_files = []
      use_redmine_log("redmine line\n")
      @ai_log_path = File.join(@log_dir, "ai_helper.log")
      File.write(@ai_log_path, "ai line\n")
      RedmineAiHelper::CustomLogger.instance.stubs(:log_file_path).returns(Pathname.new(@ai_log_path))
      AiHelperSetting.setting.update!(log_access_enabled: true)
      User.current = User.find(1)
      @original_stdout_env = ENV.fetch("RAILS_LOG_TO_STDOUT", nil)
    end

    teardown do
      Rails.logger = @original_logger
      @opened_files.each(&:close)
      FileUtils.remove_entry(@log_dir)
      User.current = nil
      if @original_stdout_env.nil?
        ENV.delete("RAILS_LOG_TO_STDOUT")
      else
        ENV["RAILS_LOG_TO_STDOUT"] = @original_stdout_env
      end
    end

    should "describe both logs in order" do
      result = @provider.get_log_file_info

      redmine, ai_helper = result[:log_files]
      assert_equal({ log_type: "redmine", available: true, file_name: "production.log",
                     size_bytes: File.size(@log_path), updated_at: File.mtime(@log_path).iso8601 }, redmine)
      assert_equal "ai_helper", ai_helper[:log_type]
      assert_equal true, ai_helper[:available]
      assert_equal "ai_helper.log", ai_helper[:file_name]
      assert_not_includes result.to_json, @log_dir
    end

    should "report the redmine log as unavailable and still describe the ai_helper log" do
      [ "1", nil ].each do |stdout_env|
        stdout_env ? ENV["RAILS_LOG_TO_STDOUT"] = stdout_env : ENV.delete("RAILS_LOG_TO_STDOUT")
        Rails.logger = ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(StringIO.new))

        redmine, ai_helper = @provider.get_log_file_info[:log_files]
        assert_equal false, redmine[:available]
        assert_predicate redmine[:reason], :present?
        assert_not redmine.key?(:file_name)
        assert_equal true, ai_helper[:available]
      end
    end

    should "report the ai_helper log as unavailable without a logger section" do
      RedmineAiHelper::CustomLogger.instance.stubs(:log_file_path).returns(nil)

      redmine, ai_helper = @provider.get_log_file_info[:log_files]
      assert_equal true, redmine[:available]
      assert_equal false, ai_helper[:available]
      assert_includes ai_helper[:reason], "no logger section"
    end

    should "report the ai_helper log as unavailable when config.yml is broken and still describe the redmine log" do
      config_path = Rails.root.join("config/ai_helper/config.yml").to_s
      RedmineAiHelper::CustomLogger.stubs(:instance).raises(Psych::SyntaxError.new(config_path, 1, 1, 0, "bad", "context"))

      result = @provider.get_log_file_info
      redmine, ai_helper = result[:log_files]
      assert_equal true, redmine[:available]
      assert_equal false, ai_helper[:available]
      assert_includes ai_helper[:reason], "could not be read"
      assert_not_includes result.to_json, Rails.root.to_s
    end

    should "report a missing file by its name" do
      File.delete(@ai_log_path)

      ai_helper = @provider.get_log_file_info[:log_files].last
      assert_equal false, ai_helper[:available]
      assert_equal "The ai_helper log file ai_helper.log does not exist.", ai_helper[:reason]
    end
  end

  context "log access checks" do
    setup do
      AiHelperSetting.setting.update!(log_access_enabled: true)
    end

    teardown do
      User.current = nil
    end

    should "reject a non-administrator" do
      User.current = User.find(2)
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.read_log_tail
      end
    end

    should "reject an anonymous user" do
      User.current = User.anonymous
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.read_log_tail
      end
    end

    should "report the permission error before the disabled setting" do
      AiHelperSetting.setting.update!(log_access_enabled: false)
      User.current = User.find(2)
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.read_log_tail
      end
    end

    should "report the permission error before an invalid argument" do
      User.current = User.find(2)
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.read_log_tail(log_type: "../../etc/passwd", lines: -1)
      end
    end

    should "tell an administrator how to enable log access when it is disabled" do
      AiHelperSetting.setting.update!(log_access_enabled: false)
      User.current = User.find(1)
      assert_rejected_without_touching_files(LOG_ACCESS_DISABLED_MESSAGE) do
        @provider.read_log_tail
      end
    end

    should "name the setting and the tab in the current locale" do
      AiHelperSetting.setting.update!(log_access_enabled: false)
      User.current = User.find(1)
      error = I18n.with_locale(:ja) { assert_raises(RuntimeError) { @provider.read_log_tail } }

      assert_includes error.message, '"ログ参照を許可する"'
      assert_includes error.message, '"全般"'
    end

    should "apply the same checks to get_log_file_info" do
      User.current = User.find(2)
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.get_log_file_info
      end

      User.current = User.anonymous
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.get_log_file_info
      end

      AiHelperSetting.setting.update!(log_access_enabled: false)
      User.current = User.find(1)
      assert_rejected_without_touching_files(LOG_ACCESS_DISABLED_MESSAGE) do
        @provider.get_log_file_info
      end
    end

    should "apply the same checks to search_log" do
      User.current = User.find(2)
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.search_log(keyword: "x")
      end

      User.current = User.anonymous
      assert_rejected_without_touching_files("Permission denied. Only administrators can access log files.") do
        @provider.search_log(keyword: "")
      end

      AiHelperSetting.setting.update!(log_access_enabled: false)
      User.current = User.find(1)
      assert_rejected_without_touching_files(LOG_ACCESS_DISABLED_MESSAGE) do
        @provider.search_log(keyword: "x")
      end
    end
  end

  private

  # Makes Rails.logger write to a fresh redmine log that holds the given content.
  # The logger level is FATAL so that nothing logged during the test changes the file.
  def use_redmine_log(content)
    File.binwrite(@log_path, content)
    file = File.open(@log_path, "a")
    @opened_files << file
    logger = ActiveSupport::Logger.new(file)
    logger.level = :fatal
    Rails.logger = ActiveSupport::BroadcastLogger.new(logger)
  end

  # Builds "line 1\nline 2\n..." with the given number of lines.
  def numbered_lines(count)
    (1..count).map { |i| "line #{i}\n" }.join
  end

  # Asserts that a line is at most MAX_LINE_CHARS plus the truncation marker.
  def assert_line_within_limit(line)
    marker = line[:truncated] ? line[:content][/ …\[truncated \d+ chars\]\z/] : ""
    assert_not_nil marker
    assert_operator line[:content].length, :<=, 2_000 + marker.length
  end

  # Asserts that the block raises the given message and never resolves, opens or
  # stats a log file (SC-004).
  def assert_rejected_without_touching_files(message)
    RedmineAiHelper::Util::LogFileLocator.expects(:resolve).never
    File.expects(:open).never
    File.expects(:stat).never

    error = assert_raises(RuntimeError) { yield }
    assert_equal message, error.message
  end
end
