# Redmine AI Helper Plugin - AI Coding Instructions

## Project Architecture

This is a **Redmine plugin** that adds AI-powered chat functionality using a **multi-agent architecture** backed by RubyLLM for LLM interactions. The plugin extends Redmine's Rails application with specialized agents for different domains.

### Request Flow

```
Controller (AiHelperController)
  → RedmineAiHelper::Llm          # Entry point from controllers, creates Langfuse trace
    → LeaderAgent#perform_user_request  # Generates goal, steps, coordinates agents
      → BaseAgent#chat             # Direct RubyLLM.chat (no tools)
      → BaseAgent#assistant        # AssistantProvider → RubyLLM::Chat with tools
        → LlmProvider.get_llm_provider  # Returns OpenAI/Anthropic/Gemini/Azure/Compatible
          → Provider#create_chat   # Configures and returns RubyLLM::Chat instance
```

### Multi-Agent System

**Automatic Registration:**
- All agents inherit from `BaseAgent` (`lib/redmine_ai_helper/base_agent.rb`)
- Agent classes **auto-register** via `inherited` hook when loaded — no manual registration needed
- `LeaderAgent` coordinates multi-step tasks by routing to specialized agents

**Key Agents:**
- Domain-specific: `IssueAgent`, `RepositoryAgent`, `WikiAgent`, `ProjectAgent`, `BoardAgent`, `SystemAgent`, `UserAgent`, `VersionAgent`, `DocumentationAgent`
- Issue updates: `IssueUpdateAgent`
- Coordination: `LeaderAgent`
- Dynamic MCP integration: `McpAgent` (generates `SubMcpAgent` classes per MCP server)

### Tool System

Tools are defined via a DSL in `BaseTools` subclasses that generates `RubyLLM::Tool` subclasses:

```ruby
class MyTools < RedmineAiHelper::BaseTools
  define_function :do_something, description: "Does something" do
    property :input, type: "string", description: "The input", required: true
  end

  def do_something(input:)
    # implementation
  end
end
```

Agents expose tools by overriding `available_tool_providers` to return an array of `BaseTools` subclasses (e.g. `[MyTools]`). The base `available_tool_classes` method then calls `available_tool_providers` and expands each provider via `.tool_classes`, returning a flat array of `RubyLLM::Tool` subclasses passed to `RubyLLM::Chat#with_tools`.

### LLM Providers

`lib/redmine_ai_helper/llm_client/` — each provider subclass implements `configure_ruby_llm` (sets API keys) and optionally overrides `create_chat`. Supported: OpenAI, Anthropic, Gemini, Azure OpenAI, OpenAI-compatible.

### Langfuse Observability

- `LangfuseWrapper` manages traces and spans at the orchestration level (`Llm` class)
- `BaseAgent#setup_langfuse_callbacks` registers `on_end_message` callbacks on `RubyLLM::Chat` instances to create Langfuse generations with token usage
- Configuration: `config/ai_helper/config.yml`

### Streaming

`AiHelper::Streaming` concern provides SSE streaming via `stream_llm_response`. Agents accept a `stream_proc` callback for incremental content delivery.

### Custom Commands

Users define reusable commands (global/project/user scoped) stored in `AiHelperCustomCommand`. `CustomCommandExpander` expands `/command_name input` syntax with template variables (`{input}`, `{user_name}`, `{project_name}`, `{datetime}`).

## Development Conventions

**Code Comments & Messages:**
- Write source code comments in **English**
- All user-facing text must support **i18n** (use `config/locales/*.yml`)
- Git commit messages in **English**
- Do not include any information about Claude Code in commit messages

**Design Document Adherence:**
**CRITICAL: Design documents in `specs/` directory are AUTHORITATIVE and MANDATORY.**
- **NEVER deviate from design documents** without explicit user approval
- Follow design documents exactly for architecture, file locations, method placement, APIs, and test locations
- If you believe the design has issues, **ASK THE USER FIRST** before implementing differently

**Test-Driven Development (TDD):**
This project follows Test-Driven Development. **Always write tests BEFORE implementing features.**

TDD Workflow:
1. **Red**: Write a failing test first that describes the expected behavior
2. **Green**: Write the minimum code necessary to make the test pass
3. **Refactor**: Improve the code while keeping tests green

TDD Rules:
- **Never write production code without a failing test first**
- When fixing a bug, first write a test that reproduces the bug, then fix it
- When adding a feature, write tests for the feature first, then implement
- Run tests frequently during development to ensure nothing breaks

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

**Running Tests:**
```bash
# Run all plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# Run a single test file
bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/unit/base_agent_test.rb

# Run tests matching a pattern
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper TESTOPTS="--name=/test_name_pattern/"

# Setup test environment (first time only)
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# YARD documentation coverage
yard stats --list-undoc
```

**Testing Guidelines:**
- Use `shoulda` (context/should blocks), not rspec
- Use `mocha` for mocking - but only when connecting to external servers
- Aim for test coverage of 95% or higher (check `coverage/` directory)
- Test structure:
  - `test/functional/` - Controller tests
  - `test/unit/` - Model, agent, and tool tests
  - `test/integration/` - API and integration tests
- Use `model_factory.rb` for creating test fixtures

**Code Style (Ruby):**
- Follow Ruby on Rails conventions
- Write comments in English
- Use `ai_helper_logger` for logging, never `Rails.logger`

**Code Style (JavaScript):**
- Use `let` and `const`, not `var`
- Vanilla JavaScript only, no jQuery
- Write comments in English

**Error Handling:**
- **NEVER implement fallback error handling** — fallbacks hide real problems
- Let errors surface immediately for proper diagnosis
- Use proper error logging, but never silently continue with fallback behavior
- Custom logger: `RedmineAiHelper::Logger` mixin
- Graceful degradation when AI services unavailable

**CSS:**
- No custom colors or fonts — use Redmine's class definitions and design system
- Use Redmine's `.box` class for container elements

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
- MCP servers configured in `config/ai_helper/config.json`
- `McpServerLoader` auto-generates `SubMcpAgent` classes per server

## Development Workflows

**Testing Setup:**
```bash
# Setup test environment
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run all plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# Run migrations
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

**Adding New Agents:**
1. Create `lib/redmine_ai_helper/agents/your_agent.rb` inheriting from `BaseAgent`
2. Implement required methods: `backstory`, `available_tool_providers`
3. Create corresponding tools class in `lib/redmine_ai_helper/tools/`
4. Agent auto-registers via inheritance hook
5. See `example/redmine_fortune/` for a complete example

**Configuration Management:**
- Global settings: `AiHelperSetting` model
- Project settings: `AiHelperProjectSetting` model
- Model profiles: `AiHelperModelProfile` for different LLM configs
- Plugin config: `config/config.yaml.example`

## Key Components

- `lib/redmine_ai_helper/llm.rb` — Entry point from controllers, wraps all agent calls with Langfuse traces
- `lib/redmine_ai_helper/base_agent.rb` — Agent base class: `chat`, `assistant`, `perform_task`, `setup_langfuse_callbacks`
- `lib/redmine_ai_helper/base_tools.rb` — Tool DSL: `define_function`/`property`/`item` → `RubyLLM::Tool` generation
- `lib/redmine_ai_helper/assistant.rb` — Wraps `RubyLLM::Chat` with unified interface (`add_message`, `run`, `messages`)
- `lib/redmine_ai_helper/assistant_provider.rb` — Factory: creates Assistant from LLM provider + instructions + tools
- `app/controllers/ai_helper_controller.rb` — Main controller with streaming support
- `assets/prompt_templates/` — Internationalized YAML prompt templates (EN/JP)
- `config/ai_helper/config.json` — MCP server configuration
- `config/ai_helper/config.yml` — Langfuse configuration

## Critical Implementation Details

**Frontend Security:**
- Build HTML structures in ERB templates (`*.html.erb`), not in JavaScript
- This prevents XSS and JS injection vulnerabilities by leveraging Rails' automatic escaping
- JavaScript should only manipulate existing DOM elements rendered by ERB
- Use `sprite_icon` helper for icons, `t()` / `l()` for i18n text in templates

**Langfuse Integration:**
- `LangfuseWrapper` manages traces and spans at the orchestration level (`Llm` class)
- `BaseAgent#setup_langfuse_callbacks` registers `on_end_message` callbacks on `RubyLLM::Chat` instances to create Langfuse generations with token usage
- LLM observability for all providers via `langfuse_util/`
- Trace conversations and agent interactions
- Configuration: `config/ai_helper/config.yml`

**Memory Management:**
- Conversations stored in `AiHelperConversation`/`AiHelperMessage` models
- Summary caching in `AiHelperSummaryCache` to avoid re-computation
- Vector data cleanup via scheduled tasks

**Error Handling:**
- **NEVER implement fallback error handling** — fallbacks hide real problems
- Let errors surface immediately for proper diagnosis
- Use proper error logging, but never silently continue with fallback behavior
- Custom logger: `RedmineAiHelper::Logger` mixin
- Graceful degradation when AI services unavailable
