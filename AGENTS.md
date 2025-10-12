# Repository Guidelines

## Project Structure & Architecture
- Plugin code follows Rails conventions: controllers/views in `app/`, models in `app/models/`, shared helpers in `app/helpers/`.
- Core engine, agents, tools, transports, and vector utilities live under `lib/redmine_ai_helper/`. Key classes include `BaseAgent`, `LeaderAgent`, and auto-generated MCP agents.
- Frontend assets are split into `assets/javascripts/` (Markdown streaming, health UI) and `assets/stylesheets/` (extends Redmine themes). Prompt templates reside in `assets/prompt_templates/`.
- Tests use Redmine’s minitest layout in `test/functional/` and `test/unit/`; architectural specs and plans sit in `specs/`.

## Build, Test, and Development Commands
- `bundle install` — install plugin dependencies (run in Redmine root).
- `bundle exec rake redmine:plugins:migrate RAILS_ENV=test` — prepare the test database; pair with `bundle exec rake redmine:plugins:ai_helper:setup_scm` for SCM fixtures.
- `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper` — execute unit and functional suites; coverage outputs to `coverage/`.
- Vector maintenance: `bundle exec rake redmine:plugins:ai_helper:vector:generate`, `:regist`, `:destroy` (set `RAILS_ENV=production` when operating on live data).

## Coding Style & Naming Conventions
- Ruby: two-space indent, snake_case methods, CamelCase classes, comments in English. Never fall back silently—surface errors promptly.
- JavaScript: ES6 modules, `const`/`let`, no jQuery; target DOM elements defined by Redmine’s layout. CSS should reuse `.box` and other Redmine tokens—avoid custom color palettes.
- Logging must use `ai_helper_logger`; direct `Rails.logger` usage is prohibited.

## Testing Expectations
- Follow `shoulda`-style minitest helpers; mock external services sparingly.
- Aim for ≥95% line coverage. Place controller flows in `test/functional/`, business logic in `test/unit/`, and agent-specific fixtures alongside their targets.
- Before PRs, run the full plugin suite and document results.

## Configuration & Setup Notes
- Global settings come from `AiHelperSetting`; per-project overrides use `AiHelperProjectSetting`.
- MCP endpoints are defined in `config/ai_helper/config.json`, which triggers dynamic `SubMcpAgent` generation for STDIO/HTTP/SSE transports.
- Langfuse integration is configured via `config/ai_helper/config.yml`; prompt files support English and Japanese locales.

## Commit & Pull Request Guidelines
- Commit messages should be concise imperatives (e.g., “Add health report history actions”). Avoid references to external coding assistants.
- PRs must summarize the change set, list executed commands/tests, and link related Redmine issues. Include UI screenshots when altering frontend behavior.
