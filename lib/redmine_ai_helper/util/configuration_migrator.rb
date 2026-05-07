# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Configuration migrator for MCP transport settings
    # Since transport type is now auto-detected from command/url presence,
    # migration is mainly for cleaning up and normalizing configuration format
    class ConfigurationMigrator
      class << self
        # Migrate configuration to support new transport abstraction
        # No longer adds 'transport' field since it's auto-detected
        # @param config [Hash] Original configuration
        # @return [Hash] Migrated configuration
        def migrate_config(config)
          return {} unless config.is_a?(Hash)
          
          migrated_config = config.deep_dup
          
          # Migrate mcpServers if present
          if migrated_config["mcpServers"]
            migrated_config["mcpServers"] = migrate_mcp_servers(migrated_config["mcpServers"])
          end
          
          migrated_config
        end

        # Check if configuration needs migration
        # Now mainly checks for format/structure issues rather than missing transport field
        # @param config [Hash] Configuration to check
        # @return [Boolean] True if migration is needed
        def needs_migration?(config)
          return false unless config.is_a?(Hash)
          return false unless config["mcpServers"]
          
          config["mcpServers"].any? do |_name, server_config|
            needs_server_migration?(server_config)
          end
        end

        # Get migration information for debugging
        # @param config [Hash] Configuration
        # @return [Hash] Migration information
        def migration_info(config)
          return { needs_migration: false, servers: {} } unless config.is_a?(Hash)
          return { needs_migration: false, servers: {} } unless config["mcpServers"]
          
          servers = {}
          needs_migration = false
          
          config["mcpServers"].each do |name, server_config|
            server_needs_migration = needs_server_migration?(server_config)
            needs_migration ||= server_needs_migration
            
            servers[name] = {
              needs_migration: server_needs_migration,
              current_transport: detect_transport_type(server_config),
              has_explicit_transport: server_config.key?("transport")
            }
          end
          
          {
            needs_migration: needs_migration,
            servers: servers
          }
        end

        private

        # Migrate mcpServers configuration
        # @param mcp_servers [Hash] MCP servers configuration
        # @return [Hash] Migrated servers configuration
        def migrate_mcp_servers(mcp_servers)
          return {} unless mcp_servers.is_a?(Hash)
          
          migrated_servers = {}
          
          mcp_servers.each do |name, server_config|
            migrated_servers[name] = migrate_server_config(server_config)
          end
          
          migrated_servers
        end

        # Migrate individual server configuration
        # @param server_config [Hash] Server configuration
        # @return [Hash] Migrated server configuration
        def migrate_server_config(server_config)
          return server_config unless server_config.is_a?(Hash)
          
          migrated = server_config.dup
          
          # Remove explicit transport field if present (auto-detection is preferred)
          migrated.delete("transport")
          
          # Detect transport type and apply transport-specific migrations
          transport_type = detect_transport_type(server_config)
          
          case transport_type
          when "stdio"
            migrate_stdio_config(migrated)
          when "http"
            migrate_http_config(migrated)
          else
            migrated
          end
        end

        # Detect transport type from legacy configuration
        # @param config [Hash] Server configuration
        # @return [String] Detected transport type
        def detect_transport_type(config)
          return "stdio" unless config.is_a?(Hash)
          
          # Check for HTTP indicators
          if config["url"]
            "http"
          # Check for STDIO indicators
          elsif config["command"] || config["args"]
            "stdio"
          else
            "stdio" # Default to stdio for backward compatibility
          end
        end

        # Check if server configuration needs migration
        # @param server_config [Hash] Server configuration
        # @return [Boolean] True if migration is needed
        def needs_server_migration?(server_config)
          return false unless server_config.is_a?(Hash)
          
          # Migration is needed if explicit transport field exists (should be removed)
          # or if STDIO config needs normalization
          server_config.key?("transport") || needs_stdio_normalization?(server_config)
        end
        
        # Check if STDIO configuration needs normalization
        # @param config [Hash] Configuration
        # @return [Boolean] True if normalization is needed
        def needs_stdio_normalization?(config)
          return false unless config.is_a?(Hash)
          
          # Check if command/args structure needs normalization
          if config["command"] && config["args"].nil?
            true
          elsif !config["command"] && config["args"] && config["args"].any?
            true
          else
            false
          end
        end

        # Migrate STDIO specific configuration
        # @param config [Hash] Configuration to migrate
        # @return [Hash] Migrated configuration
        def migrate_stdio_config(config)
          # Ensure command and args are properly formatted
          if config["command"] && !config["args"]
            # If only command is specified, ensure args is an empty array
            config["args"] = []
          elsif !config["command"] && config["args"]
            # If only args are specified, treat first arg as command
            if config["args"].is_a?(Array) && config["args"].any?
              config["command"] = config["args"].shift
            end
          end
          
          # Ensure env is a hash
          config["env"] ||= {}
          
          config
        end

        # Migrate HTTP specific configuration
        # @param config [Hash] Configuration to migrate
        # @return [Hash] Migrated configuration
        def migrate_http_config(config)
          # Ensure headers is a hash
          config["headers"] ||= {}
          
          # Set default timeout if not specified
          config["timeout"] ||= 30
          
          # Set default reconnect behavior
          config["reconnect"] = true unless config.key?("reconnect")
          
          # Set default max retries
          config["max_retries"] ||= 3
          
          config
        end
      end
    end
  end
end