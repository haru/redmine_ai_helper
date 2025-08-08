require_relative "../../test_helper"

class McpServerLoaderTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @loader = Util::McpServerLoader.instance
  end

  def teardown
    # Clean up dynamically generated classes after tests
    cleanup_dynamic_classes
  end

  context "McpServerLoader" do
    should "be singleton" do
      loader1 = Util::McpServerLoader.instance
      loader2 = Util::McpServerLoader.instance
      assert_same loader1, loader2
    end

    should "handle missing config file gracefully" do
      # Test case when config file doesn't exist
      original_path = Rails.root.join("config", "ai_helper", "config.json")
      backup_path = "#{original_path}.backup"
      
      # Temporarily move config file
      if File.exist?(original_path)
        File.rename(original_path, backup_path)
      end

      begin
        # Execute loading with empty configuration
        @loader.send(:generate_mcp_agent_classes)
        # Verify that no errors occur
        assert true
      ensure
        # Restore config file
        if File.exist?(backup_path)
          File.rename(backup_path, original_path)
        end
      end
    end

    should "validate server configurations correctly" do
      # Valid stdio configuration
      valid_stdio = { "type" => "stdio", "command" => "npx", "args" => ["-y", "@modelcontextprotocol/server-slack"] }
      assert @loader.send(:valid_server_config?, valid_stdio)

      # Valid HTTP configuration
      valid_http = { "type" => "http", "url" => "https://api.example.com/mcp" }
      assert @loader.send(:valid_server_config?, valid_http)

      # Valid SSE configuration
      valid_sse = { "type" => "sse", "url" => "https://api.example.com/sse" }
      assert @loader.send(:valid_server_config?, valid_sse)

      # Invalid configurations
      invalid_configs = [
        {},
        { "type" => "invalid" },
        { "type" => "stdio" },
        { "type" => "http" },
        { "type" => "http", "url" => "invalid-url" }
      ]

      invalid_configs.each do |config|
        assert_not @loader.send(:valid_server_config?, config), "Config should be invalid: #{config}"
      end
    end

    should "validate URLs correctly" do
      valid_urls = [
        "http://localhost:3000",
        "https://api.example.com/mcp",
        "https://example.com:8080/path"
      ]

      invalid_urls = [
        "ftp://example.com",
        "invalid-url",
        "",
        nil
      ]

      valid_urls.each do |url|
        assert @loader.send(:valid_url?, url), "URL should be valid: #{url}"
      end

      invalid_urls.each do |url|
        assert_not @loader.send(:valid_url?, url), "URL should be invalid: #{url}"
      end
    end

    should "build command string correctly" do
      config_with_both = { "command" => "npx", "args" => ["-y", "@modelcontextprotocol/server-slack"] }
      expected = "npx -y @modelcontextprotocol/server-slack"
      assert_equal expected, @loader.send(:build_command_string, config_with_both)

      config_command_only = { "command" => "node server.js" }
      assert_equal "node server.js", @loader.send(:build_command_string, config_command_only)

      config_args_only = { "args" => ["node", "server.js"] }
      assert_equal "node server.js", @loader.send(:build_command_string, config_args_only)
    end

    should "raise error for invalid command configuration" do
      invalid_config = {}
      assert_raises ArgumentError do
        @loader.send(:build_command_string, invalid_config)
      end
    end
  end

  private

  def cleanup_dynamic_classes
    # Delete dynamic classes generated in tests
    Object.constants.each do |const|
      if const.to_s.start_with?('AiHelperMcp') && const.to_s != 'AiHelperMcpAgent'
        begin
          Object.send(:remove_const, const)
        rescue NameError
          # Ignore if already deleted
        end
      end
    end
  end
end