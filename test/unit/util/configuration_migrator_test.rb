# frozen_string_literal: true

require "test_helper"

class ConfigurationMigratorTest < ActiveSupport::TestCase
  context "configuration migration" do
    should "preserve STDIO configuration without adding transport field" do
      old_config = {
        "mcpServers" => {
          "old_server" => {
            "command" => "npx",
            "args" => [ "-y", "test-server" ]
          }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      new_config = migrator.migrate_config(old_config)

      # Transport field should not be present (auto-detection based on command/args)
      assert_nil new_config["mcpServers"]["old_server"]["transport"]
      assert_equal "npx", new_config["mcpServers"]["old_server"]["command"]
      assert_equal [ "-y", "test-server" ], new_config["mcpServers"]["old_server"]["args"]
    end

    should "remove explicit transport field during migration" do
      existing_config = {
        "mcpServers" => {
          "http_server" => {
            "transport" => "http",
            "url" => "http://localhost:3000"
          }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      new_config = migrator.migrate_config(existing_config)

      # Transport field should be removed (auto-detection based on URL)
      assert_nil new_config["mcpServers"]["http_server"]["transport"]
      assert_equal "http://localhost:3000", new_config["mcpServers"]["http_server"]["url"]
    end

    should "preserve HTTP configuration without adding transport field" do
      config = {
        "mcpServers" => {
          "api_server" => {
            "url" => "https://api.example.com"
          }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      new_config = migrator.migrate_config(config)

      # No transport field should be added (auto-detection based on URL)
      assert_nil new_config["mcpServers"]["api_server"]["transport"]
    end

    should "preserve STDIO configuration from command presence" do
      config = {
        "mcpServers" => {
          "local_server" => {
            "command" => "node",
            "args" => [ "server.js" ]
          }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      new_config = migrator.migrate_config(config)

      # No transport field should be added (auto-detection based on command)
      assert_nil new_config["mcpServers"]["local_server"]["transport"]
      assert_equal "node", new_config["mcpServers"]["local_server"]["command"]
    end

    should "handle empty configuration" do
      migrator = RedmineAiHelper::Util::ConfigurationMigrator

      assert_equal({}, migrator.migrate_config({}))
      assert_equal({}, migrator.migrate_config(nil))
      assert_equal({}, migrator.migrate_config("invalid"))
    end

    should "handle configuration without mcpServers" do
      config = { "other_setting" => "value" }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      new_config = migrator.migrate_config(config)

      assert_equal config, new_config
    end
  end

  context "migration detection" do
    should "detect when migration is needed" do
      config = {
        "mcpServers" => {
          "server1" => { "command" => "npx" }, # No transport field
          "server2" => { "transport" => "http", "url" => "http://localhost" } # Has transport field
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator

      assert migrator.needs_migration?(config)
    end

    should "detect when migration is not needed" do
      config = {
        "mcpServers" => {
          "server1" => { "command" => "npx", "args" => [] },
          "server2" => { "url" => "http://localhost" }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator

      assert_not migrator.needs_migration?(config)
    end

    should "return false for invalid configuration" do
      migrator = RedmineAiHelper::Util::ConfigurationMigrator

      assert_not migrator.needs_migration?(nil)
      assert_not migrator.needs_migration?("invalid")
      assert_not migrator.needs_migration?({})
    end
  end

  context "migration information" do
    should "provide detailed migration information" do
      config = {
        "mcpServers" => {
          "clean_server" => { "command" => "npx", "args" => [] },
          "legacy_server" => { "transport" => "http", "url" => "http://localhost" }
        }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      info = migrator.migration_info(config)

      assert info[:needs_migration]
      assert_not info[:servers]["clean_server"][:needs_migration]
      assert_equal "stdio", info[:servers]["clean_server"][:current_transport]
      assert_not info[:servers]["clean_server"][:has_explicit_transport]

      assert info[:servers]["legacy_server"][:needs_migration]
      assert_equal "http", info[:servers]["legacy_server"][:current_transport]
      assert info[:servers]["legacy_server"][:has_explicit_transport]
    end
  end

  context "STDIO configuration migration" do
    should "normalize command and args structure" do
      config = { "command" => "node" } # No args

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      result = migrator.send(:migrate_stdio_config, config)

      assert_equal [], result["args"]
    end

    should "handle args without command" do
      config = { "args" => [ "node", "server.js" ] }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      result = migrator.send(:migrate_stdio_config, config)

      assert_equal "node", result["command"]
      assert_equal [ "server.js" ], result["args"]
    end

    should "ensure env is hash" do
      config = { "command" => "node" }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      result = migrator.send(:migrate_stdio_config, config)

      assert_equal({}, result["env"])
    end
  end

  context "HTTP configuration migration" do
    should "set default values for HTTP transport" do
      config = { "url" => "http://localhost:3000" }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      result = migrator.send(:migrate_http_config, config)

      assert_equal({}, result["headers"])
      assert_equal 30, result["timeout"]
      assert_equal true, result["reconnect"]
      assert_equal 3, result["max_retries"]
    end

    should "preserve existing HTTP settings" do
      config = {
        "url" => "http://localhost:3000",
        "timeout" => 60,
        "reconnect" => false,
        "headers" => { "Authorization" => "Bearer token" }
      }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      result = migrator.send(:migrate_http_config, config)

      assert_equal 60, result["timeout"]
      assert_equal false, result["reconnect"]
      assert_equal({ "Authorization" => "Bearer token" }, result["headers"])
    end
  end

  context "transport type detection" do
    should "detect STDIO from command" do
      config = { "command" => "npx" }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      transport_type = migrator.send(:detect_transport_type, config)

      assert_equal "stdio", transport_type
    end

    should "detect STDIO from args" do
      config = { "args" => [ "node", "server.js" ] }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      transport_type = migrator.send(:detect_transport_type, config)

      assert_equal "stdio", transport_type
    end

    should "detect HTTP from URL" do
      config = { "url" => "http://localhost:3000" }

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      transport_type = migrator.send(:detect_transport_type, config)

      assert_equal "http", transport_type
    end

    should "default to STDIO for ambiguous configuration" do
      config = {}

      migrator = RedmineAiHelper::Util::ConfigurationMigrator
      transport_type = migrator.send(:detect_transport_type, config)

      assert_equal "stdio", transport_type
    end
  end
end
