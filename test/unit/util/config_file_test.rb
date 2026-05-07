require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/config_file"

class RedmineAiHelper::Util::ConfigFileTest < ActiveSupport::TestCase
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
end
