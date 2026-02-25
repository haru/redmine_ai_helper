# Repository Guidelines

## Project Structure & Module Organization
Core Rails plugin code lives under `app/`, following standard MVC groupings (`app/controllers`, `app/models`, `app/helpers`). Engine internals, agents, transports, and utilities are in `lib/redmine_ai_helper/`—key entry points include `BaseAgent`, `LeaderAgent`, and generated `SubMcpAgent` variants. Frontend assets reside in `assets/javascripts/` and `assets/stylesheets/`, while prompt templates are kept in `assets/prompt_templates/`. Tests follow Redmine's minitest layout: controller flows in `test/functional/`, business logic in `test/unit/`, and architectural plans in `specs/`.

## Build, Test, and Development Commands
- `bundle install` — install plugin gems. Run from the Redmine root.
- `bundle exec rake redmine:plugins:migrate RAILS_ENV=test` — prep the test DB (pair with `bundle exec rake redmine:plugins:ai_helper:setup_scm` for SCM fixtures).
- `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper` — execute unit and functional suites with coverage to `coverage/`.
- `bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/unit/base_agent_test.rb` — run a single test file.
- `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper TESTOPTS="--name=/test_name_pattern/"` — run tests matching a pattern.
- `yard stats --list-undoc` — check YARD documentation coverage.
- Vector maintenance (production only): `bundle exec rake redmine:plugins:ai_helper:vector:generate`, `:regist`, `:destroy`.

## Coding Style & Naming Conventions

### Ruby
- **Indentation**: Two spaces (not tabs)
- **Naming**: snake_case for methods and variables, CamelCase for classes
- **File header**: Always start with `# frozen_string_literal: true`
- **Comments**: Write in English; use YARD-compatible format for public APIs (`@param`, `@return`)
- **Imports**: Use `require` at file top, followed by relative requires
- **Constants**: SCREAMING_SNAKE_CASE, freeze with `.freeze` for immutable values
- **Error Handling**: NEVER implement fallback error handling—let errors surface immediately. Use `ai_helper_logger` for logging, never `Rails.logger`
- **Logging**: Mixin `RedmineAiHelper::Logger` for `debug`, `info`, `warn`, `error` methods
- **TDD**: Write tests BEFORE implementing features (red-green-refactor cycle)
- **Error Handling Policy**: NEVER implement fallback error handling—fallbacks hide real problems. Let errors surface immediately for proper diagnosis. Use proper error logging, but never silently continue with fallback behavior.

### JavaScript
- **Variables**: Use `const` and `let`, never `var`
- **Style**: Vanilla JavaScript only, no jQuery
- **Classes**: Use ES6 class syntax
- **Comments**: Write in English
- **DOM**: Target Redmine-provided DOM hooks; build HTML in ERB templates for security

### CSS
- **Styles**: Use Redmine's existing class definitions (e.g., `.box`)
- **Colors/fonts**: Do NOT introduce custom colors or fonts—leverage Redmine's design system

### Testing with Shoulda
```ruby
class SomeTest < ActiveSupport::TestCase
  context "method_name" do
    should "describe expected behavior" do
      # test implementation
    end
  end
end
```
- Use `shoulda` (context/should blocks), not RSpec
- Use `mocha` for mocking—but only when connecting to external servers
- Place fixtures in `test/model_factory.rb`
- Aim for ≥95% line coverage

### Test-Driven Development (TDD)
Follow TDD: write tests BEFORE implementing features.
- Red: Write a failing test first
- Green: Write minimum code to make test pass
- Refactor: Improve code while keeping tests green
- Never write production code without a failing test
- For bug fixes, write a test that reproduces the bug first

### File Structure Patterns
- Controllers: `app/controllers/ai_helper_*.rb`
- Models: `app/models/ai_helper_*.rb`
- Agents: `lib/redmine_ai_helper/agents/*_agent.rb`
- Tools: `lib/redmine_ai_helper/tools/*_tools.rb`
- Tests: `test/unit/` and `test/functional/`

## Design Document Adherence
**CRITICAL**: Design documents in `specs/` directory are AUTHORITATIVE and MANDATORY.
- **NEVER deviate from design documents** without explicit user approval
- Follow design documents exactly for architecture, file locations, method placement, APIs, and test locations
- If you believe the design has issues, **ASK THE USER FIRST** before implementing differently

## Commit & Pull Request Guidelines
- **Commit messages**: Concise, imperative, English (e.g., "Add health report history actions")
- **PR body**: Summarize change set, list commands/tests executed, reference related Redmine issues
- **UI changes**: Include screenshots
- **Configuration impacts**: Mention vector maintenance or configuration changes

## Configuration & Agent Notes
- Global settings: `AiHelperSetting` model
- Project settings: `AiHelperProjectSetting` model
- Model profiles: `AiHelperModelProfile` for LLM configurations
- MCP endpoints: `config/ai_helper/config.json` (drives dynamic agent generation for STDIO/HTTP/SSE)
- Langfuse logging: `config/ai_helper/config.yml`
- Prompt templates: Support English and Japanese locales

## Agent & Tool Architecture
- **Request Flow**: Controller → Llm class (creates Langfuse trace) → LeaderAgent → BaseAgent/BaseTools → RubyLLM
- **Agent Registration**: All agents auto-register via `inherited` hook when loaded; inherit from `BaseAgent`
- **Tool System**: Tools defined via DSL in `BaseTools` subclasses using `define_function`/`property` that generates `RubyLLM::Tool` subclasses
- **Key Agents**: `IssueAgent`, `RepositoryAgent`, `WikiAgent`, `ProjectAgent`, `BoardAgent`, `SystemAgent`, `UserAgent`, `VersionAgent`, `DocumentationAgent`, `IssueUpdateAgent`, `LeaderAgent`, `McpAgent`
- **LLM Providers**: OpenAI, Anthropic, Gemini, Azure OpenAI, OpenAI-compatible (in `lib/redmine_ai_helper/llm_client/`)
- **Streaming Support**: `AiHelper::Streaming` concern provides SSE streaming via `stream_llm_response`. Agents accept a `stream_proc` callback for incremental content delivery
- **Langfuse Integration**: `LangfuseWrapper` manages traces and spans at the orchestration level. `BaseAgent#setup_langfuse_callbacks` registers `on_end_message` callbacks on `RubyLLM::Chat` instances to create Langfuse generations with token usage

## Key Integration Points
- **Hooks**: `init.rb` for registration, `lib/redmine_ai_helper/view_hook.rb` for UI integration
- **Patches**: Extend Redmine core classes via `*_patch.rb` files
- **Vector Search (Qdrant)**: `AiHelperVectorData` model, `lib/redmine_ai_helper/vector/`
- **MCP**: Dynamic agent generation via `McpServerLoader` from `config/ai_helper/mcp_servers/`

## Frontend Security
- Build HTML structures in ERB templates (`*.html.erb`), NOT in JavaScript
- This prevents XSS and injection vulnerabilities by leveraging Rails' automatic escaping
- JavaScript should only manipulate existing DOM elements rendered by ERB
- Use `sprite_icon` helper for icons, `t()` / `l()` for i18n text in templates

## Error Handling Best Practices
- **NEVER implement fallback error handling** — fallbacks hide real problems
- Let errors surface immediately for proper diagnosis
- Use `ai_helper_logger` for logging (mixin `RedmineAiHelper::Logger`)
- Never use `Rails.logger` directly
- Graceful degradation when AI services unavailable, but always log the error

## Linting & Quality Tools
- **Rubocop**: Run `rubocop` for Ruby style checking; config in `.rubocop.yml` if present
- **Reek**: Code smell detection—identifies complex code structures
- **Brakeman**: Security vulnerability scanning—run before deploying
- **Yard**: Documentation coverage—ensure public APIs are documented
- Configuration in `.qlty/qlty.toml` with plugins for actionlint, checkov, markdownlint, prettier, shellcheck, and trufflehog

## Internationalization
- All user-facing text must support i18n via `config/locales/*.yml`
- Use `t()` helper for translations
- Support English (en) and Japanese (ja) locales
