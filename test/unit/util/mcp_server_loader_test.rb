require_relative "../../test_helper"

class McpServerLoaderTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @loader = Util::McpServerLoader.instance
    @loader.instance_variable_set(:@agents_generated, nil)
    @agent_list = RedmineAiHelper::AgentList.instance
    agents = @agent_list.instance_variable_get(:@agents) || []
    @original_agents = agents.dup
    @existing_mcp_constants = Object.constants.select { |c| c.to_s.start_with?("AiHelperMcp") }
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
      original_path = Rails.root.join("config/ai_helper/config.json")
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
      valid_stdio = { "type" => "stdio", "command" => "npx", "args" => [ "-y", "@modelcontextprotocol/server-slack" ] }

      assert @loader.send(:valid_server_config?, valid_stdio)

      # Valid HTTP configuration
      valid_http = { "type" => "http", "url" => "https://api.example.com/mcp" }

      assert @loader.send(:valid_server_config?, valid_http)

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

    context "create_mcp_client with RubyLLM.mcp" do
      should "A1: build a stdio client from command and args as an argv array" do
        config = { "command" => "npx", "args" => [ "-y", "@modelcontextprotocol/server-filesystem", "/tmp" ] }
        RubyLLM.expects(:mcp).with(
          name: "fs",
          command: [ "npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp" ],
          env: {},
          input_requests: false
        ).returns(:client)

        assert_equal :client, @loader.send(:create_mcp_client, "fs", config.merge("type" => "stdio"))
      end

      should "A2: pass command and env through for stdio" do
        config = { "type" => "stdio", "command" => "/usr/bin/server", "env" => { "TOKEN" => "x" } }
        RubyLLM.expects(:mcp).with(name: "srv", command: [ "/usr/bin/server" ], env: { "TOKEN" => "x" }, input_requests: false).returns(:client)

        assert_equal :client, @loader.send(:create_mcp_client, "srv", config)
      end

      should "A2: use args as the argv when command is absent" do
        config = { "type" => "stdio", "args" => [ "node", "server.js" ] }
        RubyLLM.expects(:mcp).with(name: "srv", command: [ "node", "server.js" ], env: {}, input_requests: false).returns(:client)

        assert_equal :client, @loader.send(:create_mcp_client, "srv", config)
      end

      should "keep arguments containing spaces as single argv elements" do
        config = { "type" => "stdio", "command" => "node", "args" => [ "my server.js" ] }
        RubyLLM.expects(:mcp).with(name: "srv", command: [ "node", "my server.js" ], env: {}, input_requests: false).returns(:client)

        @loader.send(:create_mcp_client, "srv", config)
      end

      should "A3: build an http client with headers" do
        config = { "type" => "http", "url" => "https://mcp.example.com/mcp", "headers" => { "Authorization" => "Bearer t" } }
        RubyLLM.expects(:mcp).with(
          name: "web", url: "https://mcp.example.com/mcp", headers: { "Authorization" => "Bearer t" },
          input_requests: false
        ).returns(:client)

        assert_equal :client, @loader.send(:create_mcp_client, "web", config)
      end

      should "A3: default headers to an empty hash" do
        config = { "type" => "http", "url" => "https://mcp.example.com/mcp" }
        RubyLLM.expects(:mcp).with(name: "web", url: "https://mcp.example.com/mcp", headers: {}, input_requests: false).returns(:client)

        @loader.send(:create_mcp_client, "web", config)
      end

      should "not support the sse type" do
        RubyLLM.expects(:mcp).never

        assert_raises(ArgumentError) do
          @loader.send(:create_mcp_client, "sse_server", { "type" => "sse", "url" => "https://stream.example.com" })
        end
      end
    end

    context "valid_server_config? transport restrictions" do
      setup do
        @warnings = []
        warnings = @warnings
        logger = mock("logger")
        logger.stubs(:debug)
        logger.stubs(:info)
        logger.stubs(:error)
        logger.stubs(:warn).with { |msg| warnings << msg; true }
        @loader.stubs(:ai_helper_logger).returns(logger)
      end

      should "A4/A5: accept plain http on loopback hosts" do
        [ "http://localhost:8080/mcp", "http://127.0.0.1:8080/mcp", "http://[::1]:8080/mcp" ].each do |url|
          assert @loader.send(:valid_server_config?, { "type" => "http", "url" => url }), "should accept #{url}"
        end
        assert_empty @warnings
      end

      should "accept https" do
        assert @loader.send(:valid_server_config?, { "url" => "https://mcp.example.com/mcp" })
      end

      should "R1: reject the sse type with a migration warning" do
        assert_not @loader.send(:valid_server_config?, { "type" => "sse", "url" => "https://mcp.context7.com/sse" })
        assert_equal 1, @warnings.size
        assert_includes @warnings.first, "uses the SSE transport, which is no longer supported"
        assert_includes @warnings.first, "Streamable HTTP transport (\"type\": \"http\")"
      end

      should "R2: reject plain http on a non-loopback host" do
        assert_not @loader.send(:valid_server_config?, { "url" => "http://mcp-server:8080/mcp" })
        assert_equal 1, @warnings.size
        assert_includes @warnings.first, "https://"
        assert_includes @warnings.first, "http://mcp-server:8080/mcp"
      end

      should "R3: reject credentials in the URL and point to headers" do
        assert_not @loader.send(:valid_server_config?, { "url" => "https://user:pass@mcp.example.com/mcp" })
        assert_equal 1, @warnings.size
        assert_includes @warnings.first, "headers"
      end

      should "not leak credentials from the URL into the warning" do
        @loader.send(:valid_server_config?, { "url" => "https://user:secret@mcp.example.com/mcp" })

        assert_not_includes @warnings.first, "secret"
      end
    end

    should "R1/R2/R3: skip rejected servers and keep loading the others" do
      config = {
        "mcpServers" => {
          "old_sse" => { "type" => "sse", "url" => "https://mcp.example.com/sse" },
          "plain" => { "url" => "http://mcp-server:8080/mcp" },
          "creds" => { "url" => "https://u:p@mcp.example.com/mcp" },
          "good" => { "type" => "http", "url" => "https://mcp.example.com/mcp" }
        }
      }
      @loader.stubs(:load_config).returns(config)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(create_mock_logger)
      @loader.stubs(:ai_helper_logger).returns(create_mock_logger)
      RubyLLM.expects(:mcp).once.with(name: "good", url: "https://mcp.example.com/mcp", headers: {}, input_requests: false).returns(mock("mcp_client"))

      @loader.send(:generate_mcp_agent_classes)

      assert Object.const_defined?("AiHelperMcpGood")
      assert_not Object.const_defined?("AiHelperMcpOldSse")
      assert_not Object.const_defined?("AiHelperMcpPlain")
      assert_not Object.const_defined?("AiHelperMcpCreds")
    end

    should "pass MCP tool instances to RubyLLM::Chat#with_tools" do
      config = { "mcpServers" => { "filesystem" => { "command" => "node", "args" => [ "server.js" ] } } }
      fake_client = mock("mcp_client")
      fake_tools = build_fake_tool_instances
      fake_client.stubs(:tools).returns(fake_tools)
      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(create_mock_logger)
      Tools::McpTools.instance_variable_set(:@mcp_tool_cache, nil)
      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)
      agent = Object.const_get("AiHelperMcpFilesystem").new

      assert_equal fake_tools, agent.available_tool_classes
    end

    should "generate dynamic MCP agent subclass with cached tools and backstory" do
      config = {
        "mcpServers" => {
          "filesystem" => {
            "command" => "node",
            "args" => [ "server.js" ]
          }
        }
      }
      server_config = config["mcpServers"]["filesystem"]

      fake_client = mock("mcp_client")
      mock_logger = create_mock_logger

      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).with("filesystem", server_config).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)

      # Build fake tool instances (as RubyLLM's built-in MCP client returns)
      fake_tools = build_fake_tool_instances
      RedmineAiHelper::Tools::McpTools.expects(:generate_tool_classes).with(
        mcp_server_name: "filesystem",
        mcp_client: fake_client
      ).at_least_once.returns(fake_tools)

      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)

      klass = Object.const_get("AiHelperMcpFilesystem")
      agent = klass.new

      classes_first = agent.available_tool_classes
      classes_second = agent.available_tool_classes

      assert_equal fake_tools, classes_first
      assert_equal classes_first, classes_second
      assert_equal "ai_helper_mcp_filesystem", agent.role
      assert_equal "AiHelperMcpFilesystem", agent.name
      assert_equal "AiHelperMcpFilesystem", agent.to_s
      assert_predicate agent, :enabled?

      # available_tools should return tool info hashes
      tools_info = agent.available_tools

      assert_equal 1, tools_info.length
      assert_equal "list_dir", tools_info[0].dig(:function, :name)
      assert_equal "List directory contents", tools_info[0].dig(:function, :description)

      backstory = agent.backstory

      assert_includes backstory, "List directory contents"
      assert_same backstory, agent.backstory
    end

    context "enabled? with read_only_mode" do
      setup do
        config = {
          "mcpServers" => {
            "filesystem" => {
              "command" => "node",
              "args" => [ "server.js" ]
            }
          }
        }
        server_config = config["mcpServers"]["filesystem"]
        fake_client = mock("mcp_client")
        mock_logger = create_mock_logger

        @loader.stubs(:load_config).returns(config)
        @loader.expects(:create_mcp_client).with("filesystem", server_config).returns(fake_client)
        RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
        stub_llm_provider

        @loader.send(:generate_mcp_agent_classes)
        @agent = Object.const_get("AiHelperMcpFilesystem").new
      end

      should "return false when read_only_mode is enabled" do
        AiHelperSetting.stubs(:read_only_mode?).returns(true)

        assert_equal false, @agent.enabled?
      end

      should "return true when read_only_mode is disabled" do
        AiHelperSetting.stubs(:read_only_mode?).returns(false)

        assert_equal true, @agent.enabled?
      end
    end

    context "can_write? for a generated MCP agent (FR-004a)" do
      setup do
        config = {
          "mcpServers" => {
            "filesystem" => {
              "command" => "node",
              "args" => [ "server.js" ]
            }
          }
        }
        server_config = config["mcpServers"]["filesystem"]
        fake_client = mock("mcp_client")
        mock_logger = create_mock_logger

        @loader.stubs(:load_config).returns(config)
        @loader.expects(:create_mcp_client).with("filesystem", server_config).returns(fake_client)
        RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
        # Tools coming from an external MCP server carry no write/read classification,
        # so they do not respond to write_tool? (see ADR-005).
        RedmineAiHelper::Tools::McpTools.stubs(:generate_tool_classes).returns(build_fake_tool_instances)
        stub_llm_provider

        @loader.send(:generate_mcp_agent_classes)
        @agent = Object.const_get("AiHelperMcpFilesystem").new
      end

      should "report itself as write-capable instead of raising on unclassified tools" do
        AiHelperSetting.stubs(:read_only_mode?).returns(false)

        assert_equal true, @agent.can_write?
      end

      should "not depend on the tools responding to write_tool?" do
        AiHelperSetting.stubs(:read_only_mode?).returns(false)

        assert @agent.available_tool_classes.none? { |tool| tool.respond_to?(:write_tool?) },
               "the fixture must model unclassified MCP tools"
        assert_equal true, @agent.can_write?
      end
    end

    should "not log the server config of a rejected server" do
      config = {
        "mcpServers" => {
          "leaky" => { "url" => "https://user:secret@mcp.example.com/mcp", "headers" => { "Authorization" => "Bearer top-secret" } }
        }
      }
      messages = []
      mock_logger = create_mock_logger
      mock_logger.stubs(:warn).with { |m| messages << m }
      mock_logger.stubs(:error).with { |m| messages << m }
      @loader.stubs(:load_config).returns(config)
      @loader.stubs(:ai_helper_logger).returns(mock_logger)
      RubyLLM.expects(:mcp).never

      @loader.send(:generate_mcp_agent_classes)

      assert(messages.any? { |m| m.include?("'leaky'") })
      assert(messages.none? { |m| m.include?("secret") || m.include?("top-secret") })
    end

    should "reject stdio configs with a non-array args or non-hash env" do
      assert_equal false, @loader.send(:valid_server_config?, { "command" => "node", "args" => "server.js" }, "a")
      assert_equal false, @loader.send(:valid_server_config?, { "command" => "node", "env" => "X=1" }, "a")
      assert_equal false, @loader.send(:valid_server_config?, { "args" => [] }, "a")
      assert_equal false, @loader.send(:valid_server_config?, { "url" => "https://x.example.com", "headers" => [] }, "a")
    end

    should "propagate errors when tool generation fails" do
      config = { "mcpServers" => { "filesystem" => { "command" => "node", "args" => [ "server.js" ] } } }
      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).returns(mock("mcp_client"))

      stub_llm_provider

      @loader.send(:generate_mcp_agent_classes)
      agent = Object.const_get("AiHelperMcpFilesystem").new
      RedmineAiHelper::Tools::McpTools.stubs(:generate_tool_classes).raises(StandardError.new("boom"))

      error = assert_raises(StandardError) { agent.available_tool_classes }
      assert_equal "boom", error.message
    end

    should "propagate errors when tool list retrieval fails in backstory" do
      config = {
        "mcpServers" => {
          "filesystem" => {
            "command" => "node",
            "args" => [ "server.js" ]
          }
        }
      }

      fake_client = mock("mcp_client")
      mock_logger = create_mock_logger
      mock_logger.expects(:error).with(includes("Error retrieving tools information for 'filesystem': tool failure"))

      @loader.stubs(:load_config).returns(config)
      @loader.expects(:create_mcp_client).returns(fake_client)
      RedmineAiHelper::CustomLogger.stubs(:instance).returns(mock_logger)
      RedmineAiHelper::Tools::McpTools.stubs(:generate_tool_classes).returns(build_fake_tool_instances)

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
      inferred_config = { "type" => "stdio", "command" => "node", "args" => [ "worker.js" ] }

      @loader.expects(:create_stdio_client).with("stdio_server", stdio_config).returns(:stdio_client)
      @loader.expects(:create_http_client).with("http_server", http_config).returns(:http_client)
      @loader.expects(:create_stdio_client).with("inferred_server", inferred_config).returns(:inferred_client)

      assert_equal :stdio_client, @loader.send(:create_mcp_client, "stdio_server", stdio_config)
      assert_equal :http_client, @loader.send(:create_mcp_client, "http_server", http_config)
      assert_equal :inferred_client, @loader.send(:create_mcp_client, "inferred_server", inferred_config)

      assert_raises(ArgumentError) do
        @loader.send(:create_mcp_client, "invalid", { "type" => "unknown" })
      end
    end

    should "infer missing server type during validation" do
      config = { "command" => "node", "args" => [ "server.js" ] }

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
      [ :debug, :info, :warn, :error ].each do |level|
        logger.stubs(level)
      end
    end
  end

  def stub_llm_provider
    fake_provider = mock("llm_provider")
    fake_provider.stubs(:model_name).returns("gpt-4")
    fake_provider.stubs(:temperature).returns(nil)
    fake_provider.stubs(:create_chat).returns(mock("chat"))
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(fake_provider)
    RedmineAiHelper::LlmProvider.stubs(:type).returns("OpenAI")
  end

  def build_fake_tool_instances
    # Create fake tool instances that respond to .name and .description
    # (like RubyLLM::MCP::Tool instances)
    [
      Struct.new(:name, :description).new("list_dir", "List directory contents")
    ]
  end

  def cleanup_dynamic_classes
    # Delete only dynamic classes generated during the test, preserving pre-existing constants
    Object.constants.each do |const|
      if const.to_s.start_with?("AiHelperMcp") && @existing_mcp_constants.exclude?(const)
        begin
          Object.send(:remove_const, const)
        rescue NameError
          # Ignore if already deleted
        end
      end
    end
  end
end
