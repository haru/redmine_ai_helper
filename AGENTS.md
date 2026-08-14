# Repository Guidelines

## Project Overview
Redmine AI Helper Plugin — a Ruby on Rails plugin that adds AI-powered chat to Redmine. Uses a multi-agent architecture backed by RubyLLM for LLM interactions.

## Build, Test, and Development Commands
All `bundle` commands run from the **Redmine root** (`/usr/local/redmine`), not the plugin directory.

```bash
# Install gems
bundle install

# Prep test DB (run in order; setup_scm needs migrations applied first)
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run full plugin test suite (outputs coverage to coverage/)
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# Run a single test file
bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/unit/base_agent_test.rb

# Run tests matching a pattern
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper TESTOPTS="--name=/test_name_pattern/"

# RuboCop (must use --ignore-parent-exclusion to avoid Redmine root's config)
rubocop --ignore-parent-exclusion

# Regression check (YARD 100% → RuboCop → full test suite)
.devcontainer/regression-check.sh

# YARD doc coverage
yard stats --list-undoc

# Vector maintenance (production only)
bundle exec rake redmine:plugins:ai_helper:vector:generate
bundle exec rake redmine:plugins:ai_helper:vector:regist
bundle exec rake redmine:plugins:ai_helper:vector:destroy
```

## Specification & Design Reference
- **Design docs in `specs/` are AUTHORITATIVE and MANDATORY** — never deviate without explicit user approval
- For existing feature specifications and architectural decisions, consult `wiki/INDEX.md`

## Architecture Overview

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

- **Agent registration**: All agents auto-register via `inherited` hook; inherit from `BaseAgent`
- **Tool system**: `BaseTools` DSL (`define_function`/`property`) generates `RubyLLM::Tool` subclasses. `BaseAgent#available_tool_providers` returns the tool classes to use.
- **Read-only mode**: `BaseTools.define_function` accepts `write: true`. Write tools are dropped when `AiHelperSetting.read_only_mode?`. External MCP sub-agents are disabled wholesale. See ADR-005 and ADR-015.
- **LLM providers**: OpenAI, Anthropic, Gemini, Azure OpenAI, OpenAI-compatible (`lib/redmine_ai_helper/llm_client/`); each provider subclass implements `configure_ruby_llm` (sets API keys) and optionally overrides `create_chat`
- **Streaming**: `AiHelper::Streaming` concern provides SSE streaming via `stream_llm_response`; agents accept a `stream_proc` callback for incremental content delivery
- **Langfuse observability**: `LangfuseWrapper` manages traces and spans at the orchestration level (`Llm` class); `BaseAgent#setup_langfuse_callbacks` registers `on_end_message` callbacks on `RubyLLM::Chat` instances to create Langfuse generations with token usage
- **Custom commands**: Users define reusable commands (global/project/user scoped) stored in `AiHelperCustomCommand`. `CustomCommandExpander` expands `/command_name input` syntax with template variables (`{input}`, `{user_name}`, `{project_name}`, `{datetime}`)
- **Image/multi-modal attachments**: Images attached to Issues, Wiki pages, and Board messages are sent to LLMs for visual understanding. `IssueTools`/`WikiTools`/`BoardTools` use `AttachmentImageHelper` to collect image paths; images are provided to the LLM via `BaseAgent#chat(with:)` or dedicated image tool parameters — disk paths are never embedded in the textual prompt/JSON sent to the LLM. Image detection uses Redmine's `Attachment#image?` (bmp, gif, jpg, jpe, jpeg, png, webp)

Key agents: `IssueReadAgent`, `IssueWriteAgent`, `RepositoryAgent`, `WikiAgent`, `ProjectAgent`, `BoardAgent`, `SystemAgent`, `UserAgent`, `VersionAgent`, `DocumentationAgent`, `FileAgent`, `LeaderAgent`, `McpAgent`

### Tool System DSL Example
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
Agents expose tools by overriding `available_tool_providers` to return an array of `BaseTools` subclasses (e.g. `[MyTools]`). The base `available_tool_classes` method calls `available_tool_providers` and expands each provider via `.tool_classes`, returning a flat array of `RubyLLM::Tool` subclasses passed to `RubyLLM::Chat#with_tools`.

## Data Models
- `AiHelperConversation` / `AiHelperMessage` — Chat conversation storage
- `AiHelperSummaryCache` — Cached summaries to avoid re-computation
- `AiHelperSetting` / `AiHelperProjectSetting` — Global and project-level settings
- `AiHelperModelProfile` — LLM provider configurations
- `AiHelperVectorData` — Vector embeddings for issue/wiki similarity search (Qdrant)
- `AiHelperCustomCommand` — User-defined reusable prompt commands

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

## Custom Agent Development
1. Inherit from `RedmineAiHelper::BaseAgent` — automatic registration via `inherited` hook
2. Create tools inheriting from `RedmineAiHelper::BaseTools`
3. Override `available_tool_providers` to return an array of your `BaseTools` subclasses (e.g. `[YourTools]`)
4. Override `backstory` to return the agent's system prompt context
5. See `example/redmine_fortune/` for a complete example

## Coding Conventions

### Ruby
- Follow Ruby on Rails conventions
- `# frozen_string_literal: true` at file top
- Double quotes for string literals (enforced by RuboCop)
- Write comments in English
- Logging: mixin `RedmineAiHelper::Logger`, use `ai_helper_logger` — **never** `Rails.logger`
- Error handling: **NEVER implement fallback error handling**. Let errors surface immediately. No silent continues.

### Testing
- **TDD**: Write tests before implementing features
- Framework: `shoulda` (context/should blocks) + `mocha` (mocking external servers only)
- Test fixtures: `test/model_factory.rb` (FactoryBot)
- Test structure: `test/unit/` (models, agents, tools), `test/unit/lib/` (lib classes), `test/functional/` (controllers), `test/integration/` (API)

### File Structure Patterns
- Controllers: `app/controllers/ai_helper_*.rb`
- Models: `app/models/ai_helper_*.rb`
- Agents: `lib/redmine_ai_helper/agents/*_agent.rb`
- Tools: `lib/redmine_ai_helper/tools/*_tools.rb`

### Frontend
- HTML in ERB templates only — **never build HTML in JavaScript** (XSS prevention)
- JavaScript: vanilla ES6 only (`const`/`let`, classes), no jQuery
- Write comments in English
- CSS: use Redmine's existing classes (`.box`), no custom colors/fonts
- Icons: `sprite_icon` helper; i18n: `t()` / `l()`

### Configuration
- Global settings: `AiHelperSetting` model
- Project settings: `AiHelperProjectSetting` model
- Model profiles: `AiHelperModelProfile` for LLM configurations
- MCP endpoints: `config/ai_helper/config.json` (STDIO/HTTP/SSE)
- Langfuse: `config/ai_helper/config.yml`
- Prompt templates: `assets/prompt_templates/` (English and Japanese)

## Git Workflow
- **git-flow**: `develop` is integration branch, `main` is production — always branch from `develop`
- Branch naming: `feature/NNN-description`, `bugfix/NNN-description`
- Write commit messages in plain English
- Do not include any information about Claude Code in commit messages
- **NEVER commit or push without explicit user permission**

## Documentation & ADRs
- Technical docs in `docs/`; ADRs in `docs/adr/`
- All docs/ content in English
- ADRs are **append-only** — add new ones to supersede; never modify or delete past ADRs
- Format: use template in `docs/adr/README.md`

## Internationalization
- All user-facing text via `config/locales/*.yml` using `t()` helper
- Support English (en) and Japanese (ja)

## Key Integration Points
- **Hooks**: `init.rb` (registration), `lib/redmine_ai_helper/view_hook.rb` (UI)
- **Patches**: `*_patch.rb` files extend Redmine core classes
- **MCP servers**: `McpServerLoader` generates one `SubMcpAgent` per `config.json` entry
- **MCP endpoint**: `lib/redmine_ai_helper/mcp/` exposes Redmine tools as stateless MCP server via `AiHelperMcpController`
- **Chat gateway**: `lib/redmine_ai_helper/chat_channel/` — Slack/Discord bridge, runs as separate process (`bundle exec rake redmine:plugins:ai_helper:chat_channel:gateway`)
- **Health reports**: `AiHelperHealthReport`; PDF export via `lib/redmine_ai_helper/export/pdf/`
- **Multi-modal**: Images/PDFs/audio sent to LLM via `BaseAgent#chat(with:)` — disk paths never embedded in JSON/text prompts

## Linting & Quality
- **Rubocop**: after modifying any Ruby source file, always run `rubocop --ignore-parent-exclusion` and fix all offenses before finishing; config in `.rubocop.yml`. Use the `/rubocop` skill for the full fix workflow including auto-correction and test verification.
- **Reek**: code smell detection
- **Brakeman**: security scanning
- **YARD**: doc coverage (must be 100%)
- **qlty**: config in `.qlty/qlty.toml` (actionlint, checkov, markdownlint, prettier, shellcheck, trufflehog)

<!-- SPECKIT START -->
## Active Technologies
- Ruby 3.x / Rails 7.2 + RubyLLM, ActiveRecord (Redmine ORM)
- Testing: mocha (mocking), shoulda (assertions)
- Connection test results are not persisted
- Auto-fetch uses `RubyLLM::Providers::OpenAI / Anthropic / Gemini`; no DB changes (in-memory only)
- Ruby 3.x / Rails 7.2 (Redmine 6.x plugin) + RubyLLM, ActiveRecord (Redmine ORM) (010-model-profile-copy)
- Existing `ai_helper_model_profiles` table (no new migration required) (010-model-profile-copy)

## Recent Changes
- 007-vector-model-profile: Added vector model profile support; adds `use_vector_model_profile` and `vector_model_profile_id` columns to the existing `ai_helper_settings` table (MySQL/PostgreSQL)

For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

<!-- BEGIN token-budget concise-mode -->

## Token Budget — concise mode (active)

When executing any `/speckit.*` command (constitution, specify,
clarify, plan, tasks, analyze, implement, checklist,
token-budget.*), follow these output rules:

- Do not narrate plans, intentions, or steps. Run them.
- Do not recap the user's prompt back to them.
- Do not announce file writes ("I'll create...", "Now writing..."). Just write.
- After completing the command, output only:
  1. The list of files created or changed, one per line.
  2. Any blocking question or unmet assumption, in one sentence.
  3. The single line "Done." if there is nothing else to report.
- Tables, fenced code, and structured data inside artifacts are
  unaffected — this rule governs only the chat-channel prose around
  them.
- Override on request: if the user explicitly asks "explain", "walk
  me through", "why", or "what did you do", drop concise mode for
  that single reply and answer normally.

These rules apply only inside `/speckit.*` workflows. Conversational
replies outside SDD steps are not affected.

<!-- END token-budget concise-mode -->
