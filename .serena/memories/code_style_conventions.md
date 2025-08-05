# Code Style and Conventions

## Ruby Code Style
- Follow Ruby on Rails conventions
- Write comments in English
- Use ai_helper_logger for logging (NOT Rails.logger)

## JavaScript Code Style
- Use `let` and `const` instead of `var`
- Don't use jQuery - use vanilla JavaScript only
- Write comments in English

## CSS Guidelines
- Do NOT specify custom colors or fonts
- Appearance must be unified with Redmine interface
- Use Redmine's class definitions and CSS as much as possible
- Use Redmine's standard `.box` class for container elements
- Integrate with Redmine's existing design system rather than creating custom styling

## Testing Standards
- Always add tests for new features
- Write tests using "shoulda", NOT "rspec"  
- Use mocks only when absolutely necessary (e.g., external server connections)
- Aim for 95% or higher test coverage
- Test coverage files generated in `coverage/` directory
- Test structure: functional (controllers), unit (models, agents, tools), integration tests

## File Organization
- Models: `app/models/`
- Controllers: `app/controllers/`
- Views: `app/views/`
- Core logic: `lib/redmine_ai_helper/`
- Agents: `lib/redmine_ai_helper/agents/`
- Tools: `lib/redmine_ai_helper/tools/`
- Tests: `test/` (unit, functional subdirectories)

## Commit Guidelines
- Write commit messages in plain English
- Do NOT include any information about Claude Code in commit messages

## Development Principles
- Prefer editing existing files over creating new ones
- Never create documentation files unless explicitly requested
- Follow existing patterns and conventions in the codebase