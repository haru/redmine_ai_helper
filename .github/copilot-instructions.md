# Redmine AI Helper Plugin - AI Coding Instructions

## Project Architecture

This is a **Redmine plugin** that adds AI-powered chat functionality using a **multi-agent architecture**. The plugin extends Redmine's Rails application with specialized agents for different domains.

### Core Architecture Patterns

**Multi-Agent System with Automatic Registration:**
- All agents inherit from `BaseAgent` (`lib/redmine_ai_helper/base_agent.rb`)
- Agent classes auto-register via `inherited` hook when loaded
- Each agent has specialized tools in `lib/redmine_ai_helper/tools/`
- Agent coordination happens through `ChatRoom` class

**Key Agent Types:**
```ruby
# Domain-specific agents
IssueAgent, WikiAgent, ProjectAgent, RepositoryAgent
# Coordination agent
LeaderAgent
# Dynamic MCP integration
McpAgent (generates SubMcpAgent classes per MCP server)
```

**LLM Provider Abstraction:**
- Supports OpenAI, Anthropic, Gemini, Azure OpenAI, OpenAI-compatible APIs
- Provider classes in `lib/redmine_ai_helper/llm_client/`
- Unified interface through `LlmProvider` and `AssistantProvider`

## Development Conventions

**Code Comments & Messages:**
- Write source code comments in **English**
- All user-facing text must support **i18n** (use `config/locales/*.yml`)
- Git commit messages in **English**

**Testing with Shoulda:**
```ruby
class SomeTest < ActiveSupport::TestCase
  context "method_name" do
    should "describe expected behavior" do
      # test implementation
    end
  end
end
```

**File Structure Patterns:**
- Controllers: `app/controllers/ai_helper_*.rb`
- Models: `app/models/ai_helper_*.rb`
- Agents: `lib/redmine_ai_helper/agents/*_agent.rb`
- Tools: `lib/redmine_ai_helper/tools/*_tools.rb`
- Tests: `test/unit/` and `test/functional/`

## Key Integration Points

**Redmine Plugin Hooks:**
- `init.rb` - Plugin registration and permission setup
- `lib/redmine_ai_helper/view_hook.rb` - UI integration points
- Patches: `*_patch.rb` files extend Redmine core classes

**Vector Search (Qdrant):**
- Issue/wiki content embeddings in `AiHelperVectorData` model
- Vector operations in `lib/redmine_ai_helper/vector/`
- Setup via rake tasks: `redmine:plugins:ai_helper:*`

**MCP (Model Context Protocol):**
- Dynamic agent generation per MCP server configuration
- Transport layer supports STDIO and HTTP+SSE
- Configuration in `config/ai_helper/mcp_servers/`

## Development Workflows

**Testing Setup:**
```bash
# Setup test environment
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run all plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper
```

**Adding New Agents:**
1. Create `lib/redmine_ai_helper/agents/your_agent.rb` inheriting from `BaseAgent`
2. Implement required methods: `backstory`, `available_tool_providers`
3. Create corresponding tools class in `lib/redmine_ai_helper/tools/`
4. Agent auto-registers via inheritance hook

**Configuration Management:**
- Global settings: `AiHelperSetting` model
- Project settings: `AiHelperProjectSetting` model
- Model profiles: `AiHelperModelProfile` for different LLM configs
- Plugin config: `config/config.yaml.example`

## Critical Implementation Details

**Langfuse Integration:**
- LLM observability for all providers via `langfuse_util/`
- Trace conversations and agent interactions

**Memory Management:**
- Conversations stored in `AiHelperConversation`/`AiHelperMessage` models
- Summary caching in `AiHelperSummaryCache` to avoid re-computation
- Vector data cleanup via scheduled tasks

**Error Handling:**
- Custom logger: `RedmineAiHelper::Logger` mixin
- Graceful degradation when AI services unavailable
- MCP server connection fallbacks
