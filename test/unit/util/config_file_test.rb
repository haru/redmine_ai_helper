require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/config_file"

class RedmineAiHelper::Util::ConfigFileTest < ActiveSupport::TestCase
  # Make load_config see the given parsed YAML hash.
  def stub_config(yaml)
    File.stubs(:exist?).with(@config_path).returns(true)
    YAML.stubs(:load_file).with(@config_path).returns(yaml)
  end

  # Make load_config see the given autocompletion section.
  def stub_autocompletion(section)
    stub_config({ "autocompletion" => section })
  end

  # Shorthand for the method under test.
  def settings
    RedmineAiHelper::Util::ConfigFile.autocompletion_settings
  end

  # Take the plugin logger away the way a broken config.yml does: CustomLogger
  # reads the same file, so constructing it fails while we are reporting that
  # very file. Clears the memoized logger on both sides so the stub is seen.
  def without_plugin_logger
    RedmineAiHelper::Util::ConfigFile.unstub(:ai_helper_logger)
    forget_memoized_logger
    RedmineAiHelper::CustomLogger.stubs(:instance)
      .raises(Psych::SyntaxError.new("config.yml", 1, 1, 0, "broken", "context"))
    yield
  ensure
    forget_memoized_logger
  end

  def forget_memoized_logger
    config_file = RedmineAiHelper::Util::ConfigFile
    config_file.remove_instance_variable(:@ai_helper_logger) if config_file.instance_variable_defined?(:@ai_helper_logger)
  end

  context "ConfigFile" do
    setup do
      @config_path = Rails.root.join("config/ai_helper/config.yml")
    end

    should "return an empty hash if the config file does not exist" do
      File.stubs(:exist?).with(@config_path).returns(false)
      config = RedmineAiHelper::Util::ConfigFile.load_config

      assert_equal({}, config)
    end

    should "load and symbolize keys from the config file" do
      mock_yaml = {
        "logger" => { "level" => "debug" },
        "langfuse" => { "public_key" => "test_key" }
      }
      File.stubs(:exist?).with(@config_path).returns(true)
      YAML.stubs(:load_file).with(@config_path).returns(mock_yaml)

      config = RedmineAiHelper::Util::ConfigFile.load_config
      expected_config = {
        logger: { level: "debug" },
        langfuse: { public_key: "test_key" }
      }

      assert_equal(expected_config, config)
    end

    should "return the correct config file path" do
      assert_equal @config_path, RedmineAiHelper::Util::ConfigFile.config_file_path
    end
  end

  context "ConfigFile.autocompletion_settings" do
    setup do
      @config_path = Rails.root.join("config/ai_helper/config.yml")
      @logger = mock("ai_helper_logger")
      @logger.stubs(:warn)
      RedmineAiHelper::Util::ConfigFile.stubs(:ai_helper_logger).returns(@logger)
    end

    context "when the config file does not exist" do
      setup do
        File.stubs(:exist?).with(@config_path).returns(false)
      end

      should "return defaults without logging" do
        @logger.expects(:warn).never

        assert_equal 30, settings[:timeout]
        assert_nil settings[:debounce_delay]
        assert_nil settings[:min_length]
        assert_nil settings[:suggestion_color]
      end
    end

    context "when the autocompletion section is absent" do
      setup do
        stub_config({ "langfuse" => { "public_key" => "key" } })
      end

      should "return defaults without logging" do
        @logger.expects(:warn).never

        assert_equal 30, settings[:timeout]
        assert_nil settings[:debounce_delay]
      end

      should "not touch other sections" do
        assert_equal({ public_key: "key" }, RedmineAiHelper::Util::ConfigFile.load_config[:langfuse])
      end
    end

    context "when the YAML file is broken" do
      setup do
        File.stubs(:exist?).with(@config_path).returns(true)
        YAML.stubs(:load_file).with(@config_path).raises(Psych::SyntaxError.new("config.yml", 1, 1, 0, "broken", "context"))
      end

      should "return defaults instead of raising" do
        assert_nothing_raised do
          assert_equal 30, settings[:timeout]
        end
      end

      should "log exactly one warning" do
        @logger.expects(:warn).once

        settings
      end

      # CustomLogger parses this same file the first time it is instantiated, so
      # building the plugin logger fails for exactly the reason we are trying to
      # report. That failure must not escape to the caller: ai_helper_logger
      # hands out Rails.logger instead (ADR-020).
      should "return defaults when the plugin logger itself cannot be initialised" do
        without_plugin_logger do
          Rails.logger.stubs(:warn)

          assert_nothing_raised do
            assert_equal 30, settings[:timeout]
          end
        end
      end

      should "still report the broken file when the plugin logger is unusable" do
        without_plugin_logger do
          Rails.logger.expects(:warn).with { |message| message.include?("Failed to read") }.once
          Rails.logger.expects(:warn).with { |message| message.include?("plugin logger unavailable") }.once

          settings
        end
      end
    end

    context "timeout" do
      should "use the default when the key is absent" do
        stub_autocompletion({ "min_length" => 5 })
        @logger.expects(:warn).never

        assert_equal 30, settings[:timeout]
      end

      should "accept a numeric value" do
        stub_autocompletion({ "timeout" => 45 })
        @logger.expects(:warn).never

        assert_equal 45, settings[:timeout]
      end

      should "accept a numeric string" do
        stub_autocompletion({ "timeout" => "45" })
        @logger.expects(:warn).never

        assert_equal 45, settings[:timeout]
      end

      should "accept the range boundaries" do
        stub_autocompletion({ "timeout" => 1 })
        assert_equal 1, settings[:timeout]

        stub_autocompletion({ "timeout" => 600 })
        assert_equal 600, settings[:timeout]
      end

      [ 0, -5, 601 ].each do |out_of_range|
        should "reject #{out_of_range} as out of range" do
          stub_autocompletion({ "timeout" => out_of_range })
          @logger.expects(:warn).once

          assert_equal 30, settings[:timeout]
        end
      end

      [ "abc", [ 1, 2 ], {} ].each do |not_a_number|
        should "reject #{not_a_number.inspect} as a non-number" do
          stub_autocompletion({ "timeout" => not_a_number })
          @logger.expects(:warn).once

          assert_equal 30, settings[:timeout]
        end
      end

      # YAML parses .inf / .nan into Floats whose to_i raises FloatDomainError,
      # so they have to be rejected before any arithmetic touches them.
      [ Float::INFINITY, -Float::INFINITY, Float::NAN, "Infinity" ].each do |special|
        should "reject #{special.inspect} without raising" do
          stub_autocompletion({ "timeout" => special })
          @logger.expects(:warn).once

          assert_nothing_raised do
            assert_equal 30, settings[:timeout]
          end
        end
      end

      should "name the key, the value and the reason in the warning" do
        stub_autocompletion({ "timeout" => 601 })
        @logger.expects(:warn).with do |message|
          message.include?("timeout") && message.include?("601") && message.match?(/range/i)
        end

        settings
      end
    end

    context "suggestion_color" do
      [ "#888888", "#abc", "#ABCDEF" ].each do |valid|
        should "accept #{valid}" do
          stub_autocompletion({ "suggestion_color" => valid })
          @logger.expects(:warn).never

          assert_equal valid, settings[:suggestion_color]
        end
      end

      [ "red", "#12345", "'};alert(1);//", "888888", 16777215 ].each do |invalid|
        should "reject #{invalid.inspect}" do
          stub_autocompletion({ "suggestion_color" => invalid })
          @logger.expects(:warn).once

          assert_nil settings[:suggestion_color]
        end
      end

      should "return nil without logging when the key is absent" do
        stub_autocompletion({ "timeout" => 30 })
        @logger.expects(:warn).never

        assert_nil settings[:suggestion_color]
      end
    end

    context "debounce_delay" do
      should "accept a positive number" do
        stub_autocompletion({ "debounce_delay" => 800 })
        @logger.expects(:warn).never

        assert_equal 800, settings[:debounce_delay]
      end

      [ 0, -1, "abc", [], Float::INFINITY, Float::NAN ].each do |invalid|
        should "reject #{invalid.inspect}" do
          stub_autocompletion({ "debounce_delay" => invalid })
          @logger.expects(:warn).once

          assert_nothing_raised do
            assert_nil settings[:debounce_delay]
          end
        end
      end

      should "return nil without logging when the key is absent" do
        stub_autocompletion({ "timeout" => 30 })
        @logger.expects(:warn).never

        assert_nil settings[:debounce_delay]
      end
    end

    context "min_length" do
      should "accept zero" do
        stub_autocompletion({ "min_length" => 0 })
        @logger.expects(:warn).never

        assert_equal 0, settings[:min_length]
      end

      should "accept a positive integer" do
        stub_autocompletion({ "min_length" => 12 })
        @logger.expects(:warn).never

        assert_equal 12, settings[:min_length]
      end

      [ -1, 2.5, "abc", {}, Float::INFINITY, Float::NAN ].each do |invalid|
        should "reject #{invalid.inspect}" do
          stub_autocompletion({ "min_length" => invalid })
          @logger.expects(:warn).once

          assert_nothing_raised do
            assert_nil settings[:min_length]
          end
        end
      end
    end

    # wiki_min_length predates the consolidated autocompletion section and is
    # still honoured, so an existing configuration keeps its wiki threshold.
    context "wiki_min_length" do
      should "accept a non-negative integer" do
        stub_autocompletion({ "wiki_min_length" => 8 })
        @logger.expects(:warn).never

        assert_equal 8, settings[:wiki_min_length]
      end

      should "be independent of min_length" do
        stub_autocompletion({ "min_length" => 20, "wiki_min_length" => 3 })
        @logger.expects(:warn).never

        assert_equal 20, settings[:min_length]
        assert_equal 3, settings[:wiki_min_length]
      end

      should "return nil without logging when the key is absent" do
        stub_autocompletion({ "min_length" => 20 })
        @logger.expects(:warn).never

        assert_nil settings[:wiki_min_length]
      end

      [ -1, 2.5, "abc" ].each do |invalid|
        should "reject #{invalid.inspect} and name the key in the warning" do
          stub_autocompletion({ "wiki_min_length" => invalid })
          @logger.expects(:warn).with { |message| message.include?("wiki_min_length") }.once

          assert_nil settings[:wiki_min_length]
        end
      end
    end

    context "unknown keys" do
      should "report a key the section does not understand" do
        stub_autocompletion({ "min_lenght" => 5 })
        @logger.expects(:warn).with { |message| message.include?("min_lenght") }.once

        assert_nil settings[:min_length]
      end

      should "report each unknown key once and keep the known ones" do
        stub_autocompletion({ "timeout" => 45, "typo_one" => 1, "typo_two" => 2 })
        @logger.expects(:warn).times(2)

        assert_equal 45, settings[:timeout]
      end

      should "not report any of the documented keys" do
        stub_autocompletion({
          "timeout" => 45,
          "debounce_delay" => 800,
          "min_length" => 5,
          "wiki_min_length" => 3,
          "suggestion_color" => "#abc"
        })
        @logger.expects(:warn).never

        settings
      end
    end

    context "with several invalid keys at once" do
      should "log one warning per invalid key and keep valid keys" do
        stub_autocompletion({
          "timeout" => -1,
          "debounce_delay" => "nope",
          "min_length" => 7,
          "suggestion_color" => "chartreuse"
        })
        @logger.expects(:warn).times(3)

        result = settings

        assert_equal 30, result[:timeout]
        assert_nil result[:debounce_delay]
        assert_equal 7, result[:min_length]
        assert_nil result[:suggestion_color]
      end
    end
  end
end
