# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Redmine AI Helper Plugin — a Ruby on Rails plugin that adds AI-powered chat to Redmine. Uses a multi-agent architecture backed by RubyLLM for LLM interactions.

## Development Commands

```bash
# Run all tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# Run a single test file
bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/unit/base_agent_test.rb

# Run tests matching a pattern
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper TESTOPTS="--name=/test_name_pattern/"

# Setup test environment (first time only)
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run migrations
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# YARD documentation coverage
yard stats --list-undoc
```

## Architecture

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

Agents inherit from `BaseAgent` and are **automatically registered** via the `inherited` hook — no manual registration needed. `LeaderAgent` coordinates multi-step tasks by routing to specialized agents.

Key agents: `IssueAgent`, `RepositoryAgent`, `WikiAgent`, `ProjectAgent`, `McpAgent`, `BoardAgent`, `SystemAgent`, `UserAgent`, `VersionAgent`, `IssueUpdateAgent`, `DocumentationAgent`

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

### Streaming

`AiHelper::Streaming` concern provides SSE streaming via `stream_llm_response`. Agents accept a `stream_proc` callback for incremental content delivery.

### Custom Commands

Users define reusable commands (global/project/user scoped) stored in `AiHelperCustomCommand`. `CustomCommandExpander` expands `/command_name input` syntax with template variables (`{input}`, `{user_name}`, `{project_name}`, `{datetime}`).

### MCP Integration

MCP servers configured in `config/ai_helper/config.json`. `McpServerLoader` auto-generates `SubMcpAgent` classes per server. Supports STDIO and HTTP+SSE transports (auto-detected).

### Image Attachment Support

Attached images on Issues, Wiki pages, and Board messages are sent to LLMs for visual understanding.

- **Tool flow**: `IssueTools`/`WikiTools`/`BoardTools` use `AttachmentImageHelper` to collect image paths, returning `RubyLLM::Content` (text + image attachments) when images exist
- **Summary flow**: `IssueAgent#issue_summary`/`WikiAgent#wiki_summary` pass image paths via `BaseAgent#chat(with:)` parameter
- **Security**: Disk file paths are never included in JSON text sent to the LLM — they are only passed through `RubyLLM::Content` attachments or the `with:` parameter
- **Image detection**: Uses Redmine's `Attachment#image?` (extension-based: bmp, gif, jpg, jpe, jpeg, png, webp)

## Key Components

- `lib/redmine_ai_helper/llm.rb` — Entry point from controllers, wraps all agent calls with Langfuse traces
- `lib/redmine_ai_helper/base_agent.rb` — Agent base class: `chat` (with `with:` for images), `assistant`, `perform_task`, `setup_langfuse_callbacks`
- `lib/redmine_ai_helper/base_tools.rb` — Tool DSL: `define_function`/`property`/`item` → `RubyLLM::Tool` generation
- `lib/redmine_ai_helper/assistant.rb` — Wraps `RubyLLM::Chat` with unified interface (`add_message`, `run`, `messages`)
- `lib/redmine_ai_helper/assistant_provider.rb` — Factory: creates Assistant from LLM provider + instructions + tools
- `lib/redmine_ai_helper/util/attachment_image_helper.rb` — Extracts image attachment disk paths from containers (Issue, WikiPage, Message)
- `app/controllers/ai_helper_controller.rb` — Main controller with streaming support
- `assets/prompt_templates/` — Internationalized YAML prompt templates (EN/JP)
- `config/ai_helper/config.json` — MCP server configuration
- `config/ai_helper/config.yml` — Langfuse configuration

## Development Guidelines

### Design Document Adherence
**CRITICAL: Design documents in `specs/` directory are AUTHORITATIVE and MANDATORY.**

- **NEVER deviate from design documents** without explicit user approval
- Follow design documents exactly for architecture, file locations, method placement, APIs, and test locations
- If you believe the design has issues, **ASK THE USER FIRST** before implementing differently

### Test-Driven Development (TDD)
This project follows TDD. **Always write tests BEFORE implementing features.**

1. **Red**: Write a failing test first
2. **Green**: Write minimum code to pass
3. **Refactor**: Improve while keeping tests green

Testing conventions:
- Use `shoulda` (context/should blocks), not rspec
- Use `mocha` for mocking external servers
- Test structure: `test/unit/` (models, agents, tools), `test/functional/` (controllers)
- Aim for 95%+ coverage (check `coverage/` directory)

### Code Style (Ruby)
- Follow Ruby on Rails conventions
- Write comments in English
- Use `ai_helper_logger` for logging, never `Rails.logger`

### Code Style (JavaScript)
- Use `let` and `const`, not `var`
- Vanilla JavaScript only, no jQuery
- Write comments in English

### Frontend Security
- Build HTML in ERB templates, not JavaScript (prevents XSS)
- JavaScript only manipulates existing DOM elements rendered by ERB
- Use `sprite_icon` for icons, `t()`/`l()` for i18n text in templates

### Error Handling
- **NEVER implement fallback error handling** — fallbacks hide real problems
- Let errors surface immediately for proper diagnosis
- Use proper error logging, but never silently continue with fallback behavior

### CSS
- No custom colors or fonts — use Redmine's class definitions and design system
- Use Redmine's `.box` class for container elements

## Commit Guidelines
- Do not include any information about Claude Code in commit messages
- Write commit messages in plain English

## Custom Agent Development

1. Inherit from `RedmineAiHelper::BaseAgent` — automatic registration via `inherited` hook
2. Create tools inheriting from `RedmineAiHelper::BaseTools`
3. Override `available_tool_providers` to return an array of your `BaseTools` subclasses (e.g. `[YourTools]`)
4. Override `backstory` to return the agent's system prompt context
5. See `example/redmine_fortune/` for a complete example
