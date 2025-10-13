# Repository Guidelines

## Project Structure & Module Organization
Core Rails plugin code lives under `app/`, following standard MVC groupings (`app/controllers`, `app/models`, `app/helpers`). Engine internals, agents, transports, and utilities are in `lib/redmine_ai_helper/`—key entry points include `BaseAgent`, `LeaderAgent`, and generated `SubMcpAgent` variants. Frontend assets reside in `assets/javascripts/` and `assets/stylesheets/`, while prompt templates are kept in `assets/prompt_templates/`. Tests follow Redmine’s minitest layout: controller flows in `test/functional/`, business logic in `test/unit/`, and architectural plans in `specs/`.

## Build, Test, and Development Commands
- `bundle install` — install plugin gems. Run from the Redmine root.
- `bundle exec rake redmine:plugins:migrate RAILS_ENV=test` — prep the test DB (pair with `bundle exec rake redmine:plugins:ai_helper:setup_scm` for SCM fixtures).
- `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper` — execute unit and functional suites with coverage to `coverage/`.
- Vector maintenance (production only): `bundle exec rake redmine:plugins:ai_helper:vector:generate`, `:regist`, `:destroy`.

## Coding Style & Naming Conventions
Use two-space indentation for Ruby, snake_case methods, and CamelCase classes. JavaScript should use ES6 modules with `const`/`let`, targeting DOM hooks provided by Redmine. Reuse Redmine styles such as `.box`; avoid introducing new color palettes. All logging must go through `ai_helper_logger`, never `Rails.logger`. Stick to ASCII unless the existing file justifies Unicode.

## Testing Guidelines
Tests rely on shoulda-style minitest helpers. Aim for ≥95% line coverage and keep controller specs in `test/functional/` with logic-focused cases in `test/unit/`. Place agent fixtures beside their targets. Run `bundle exec rake redmine:plugins:test NAME=redmine_ai_helper` before submitting changes and capture the command output for PR notes.

## Commit & Pull Request Guidelines
Write concise imperative commit messages (e.g., “Add health report history actions”). Pull requests must summarize the change set, list commands/tests executed, reference related Redmine issues, and include UI screenshots when frontend behavior changes. Mention any vector maintenance or configuration impacts in the PR body.

## Configuration & Agent Notes
Global settings are managed via `AiHelperSetting`; per-project overrides use `AiHelperProjectSetting`. MCP endpoints live in `config/ai_helper/config.json`, which drives dynamic agent generation for STDIO/HTTP/SSE transports. Langfuse logging is configured through `config/ai_helper/config.yml`; prompt templates support English and Japanese locales.
