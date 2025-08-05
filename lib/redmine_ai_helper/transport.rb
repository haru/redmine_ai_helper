# frozen_string_literal: true

module RedmineAiHelper
  module Transport
    # Transport module is now deprecated - replaced by ruby-mcp-client gem
    # This module is kept for backward compatibility only
    
    # @deprecated Use ruby-mcp-client gem instead
    def self.available_transports
      %w[stdio http sse streamable_http]
    end
    
    # @deprecated Use ruby-mcp-client gem instead  
    def self.create(config)
      raise NotImplementedError, "Transport layer replaced by ruby-mcp-client gem. Use MCPClient.create_client instead."
    end
    
    # @deprecated Use ruby-mcp-client gem instead
    def self.valid_config?(config)
      return false unless config.is_a?(Hash)
      !!(config['command'] || config['url'])
    end
    
    # @deprecated Use ruby-mcp-client gem instead
    def self.determine_type(config)
      return 'stdio' if config['command'] || config['args']
      return 'http' if config['url']
      'stdio'
    end
  end
end