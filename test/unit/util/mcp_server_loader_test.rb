require_relative "../../test_helper"

class McpServerLoaderTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @loader = Util::McpServerLoader.instance
    @loader.instance_variable_set(:@agents_generated, nil)
    @agent_list = RedmineAiHelper::AgentList.instance
    agents = @agent_list.instance_variable_get(:@agents) || []
    @original_agents = agents.dup
  end

  def teardown
    # Clean up dynamically generated classes after tests
    @agent_list.instance_variable_set(:@agents, @original_agents.dup) if @agent_list
    @loader.instance_variable_set(:@agents_generated, nil)
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

    should "generate dynamic MCP agent subclass with cached tools and backstory" do
      config = {
        "mcpServers" => {
          "filesystem" => {
            "command" => "node",
            "args" => ["server.js"],
          },
        },
      }
      server_config = config["mcpServers"]["filesystem"]

      fake_client = mock("mcp_client")
      mock_logger = create_mock_logger

      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).with("filesystem", server_config).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
      tool_class = build_fake_tool_class
      fake_tool_classes = tool_class.tool_classes
      RedmineAiHelper::Tools::McpTools.expects(:generate_tool_class).with(mcp_server_name: "filesystem", mcp_client: fake_client).once.returns(tool_class)

      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)

      klass = Object.const_get("AiHelperMcpFilesystem")
      agent = klass.new

      classes_first = agent.available_tool_classes
      classes_second = agent.available_tool_classes

      assert_equal fake_tool_classes, classes_first
      assert_equal classes_first, classes_second
      assert_equal "ai_helper_mcp_filesystem", agent.role
      assert_equal "AiHelperMcpFilesystem", agent.name
      assert_equal "AiHelperMcpFilesystem", agent.to_s
      assert agent.enabled?

      agent.stubs(:available_tools).returns([{ function: { description: "List directory contents" } }])
      backstory = agent.backstory
      assert_includes backstory, "List directory contents"
      assert_same backstory, agent.backstory
    end

    should "return empty tool providers and log error when tool generation fails" do
      config = {
        "mcpServers" => {
          "filesystem" => {
            "command" => "node",
            "args" => ["server.js"],
          },
        },
      }
      server_config = config["mcpServers"]["filesystem"]

      fake_client = mock("mcp_client")
      mock_logger = create_mock_logger

      mock_logger.expects(:error).with(includes("Error loading tools for MCP server 'filesystem': boom"))

      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).with("filesystem", server_config).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)

      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)
      klass = Object.const_get("AiHelperMcpFilesystem")
      agent = klass.new

      RedmineAiHelper::Tools::McpTools.stubs(:generate_tool_class).raises(StandardError.new("boom"))

      assert_equal [], agent.available_tool_providers
    end

    should "propagate errors when tool list retrieval fails in backstory" do
      config = {
        "mcpServers" => {
          "filesystem" => {
            "command" => "node",
            "args" => ["server.js"],
          },
        },
      }

      fake_client = mock("mcp_client")
      mock_logger = create_mock_logger
      mock_logger.expects(:error).with(includes("Error retrieving tools information for 'filesystem': tool failure"))

      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
      RedmineAiHelper::Tools::McpTools.stubs(:generate_tool_class).returns(build_fake_tool_class)

      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)
      klass = Object.const_get("AiHelperMcpFilesystem")
      agent = klass.new
      agent.stubs(:available_tools).raises(StandardError.new("tool failure"))

      assert_raises(StandardError) do
        agent.backstory
      end
    end

    should "create appropriate MCP client based on type and inferred configuration" do
      stdio_config = { "type" => "stdio", "command" => "node" }
      http_config = { "type" => "http", "url" => "https://api.example.com" }
      sse_config = { "type" => "sse", "url" => "https://stream.example.com" }
      inferred_config = { "command" => "node", "args" => ["worker.js"] }

      @loader.expects(:create_stdio_client).with("stdio_server", stdio_config).returns(:stdio_client)
      @loader.expects(:create_http_client).with("http_server", http_config).returns(:http_client)
      @loader.expects(:create_sse_client).with("sse_server", sse_config).returns(:sse_client)
      @loader.expects(:create_stdio_client).with("inferred_server", inferred_config).returns(:inferred_client)

      assert_equal :stdio_client, @loader.send(:create_mcp_client, "stdio_server", stdio_config)
      assert_equal :http_client, @loader.send(:create_mcp_client, "http_server", http_config)
      assert_equal :sse_client, @loader.send(:create_mcp_client, "sse_server", sse_config)
      assert_equal :inferred_client, @loader.send(:create_mcp_client, "inferred_server", inferred_config)

      assert_raises(ArgumentError) do
        @loader.send(:create_mcp_client, "invalid", { "type" => "unknown" })
      end
    end

    should "infer missing server type during validation" do
      config = { "command" => "node", "args" => ["server.js"] }
      assert @loader.send(:valid_server_config?, config)
      assert_equal "stdio", config["type"]

      http_config = { "url" => "https://example.com" }
      assert @loader.send(:valid_server_config?, http_config)
      assert_equal "http", http_config["type"]
    end
  end

  private
  def create_mock_logger
    mock("logger").tap do |logger|
      [:debug, :info, :warn, :error].each do |level|
        logger.stubs(level)
      end
    end
  end

  def stub_llm_provider
    fake_client = mock("llm_client")
    fake_client.stubs(:langfuse=)
    fake_provider = mock("llm_provider")
    fake_provider.stubs(:generate_client).returns(fake_client)
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(fake_provider)
    RedmineAiHelper::LlmProvider.stubs(:type).returns("OpenAI")
  end

  def build_fake_tool_class
    # Create a fake RubyLLM::Tool subclass with name and description
    fake_tool = Class.new do
      define_singleton_method(:name) { "RedmineAiHelper::Tools::FakeListDir" }
      define_singleton_method(:description) { "List directory contents" }
    end

    # Return a class that responds to tool_classes (like BaseTools subclasses)
    Class.new do
      define_singleton_method(:tool_classes) do
        [fake_tool]
      end
    end
  end

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
