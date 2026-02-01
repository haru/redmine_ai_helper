# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Redmine AI Helper Plugin, a Ruby on Rails plugin that adds AI-powered chat functionality to Redmine project management software. It uses a multi-agent architecture with various specialized agents for different tasks like issue management, repository analysis, and wiki content processing.

## Architecture

### Multi-Agent System
The plugin implements a multi-agent architecture where different agents handle specific domains:
- **BaseAgent** (`lib/redmine_ai_helper/base_agent.rb`) - Base class with automatic agent registration via inheritance hook
- **LeaderAgent** - Coordinates multi-step tasks across agents and manages complex workflows
- **IssueAgent** - Handles issue-related queries and operations
- **RepositoryAgent** - Manages repository and source code analysis
- **WikiAgent** - Processes wiki content and queries
- **ProjectAgent** - Project analysis and health reporting functionality
- **McpAgent** - Model Context Protocol integration with dynamic SubMcpAgent generation per server
- **BoardAgent**, **SystemAgent**, **UserAgent**, **VersionAgent**, **IssueUpdateAgent** - Handle their respective domains

### Key Components
- **LLM Providers** (`lib/redmine_ai_helper/llm_client/`) - Abstracts different AI services (OpenAI, Anthropic, Gemini, Azure OpenAI, OpenAI-compatible)
- **Tools** (`lib/redmine_ai_helper/tools/`) - Each agent has associated tools for specific operations
- **Vector Search** (`lib/redmine_ai_helper/vector/`) - Qdrant-based vector search for issues and wiki content
- **Chat Room** (`lib/redmine_ai_helper/chat_room.rb`) - Manages conversation state and agent coordination
- **MCP Transport Layer** (`lib/redmine_ai_helper/transport/`) - Multi-protocol support (STDIO, HTTP+SSE) for Model Context Protocol
- **Assistant Layer** (`lib/redmine_ai_helper/assistant.rb`) - Extends Langchain::Assistant with provider-specific implementations
- **Langfuse Integration** (`lib/redmine_ai_helper/langfuse_util/`) - LLM observability and monitoring for all providers

### Models
- `AiHelperConversation` - Stores chat conversations
- `AiHelperMessage` - Individual messages in conversations
- `AiHelperModelProfile` - AI model configurations
- `AiHelperSetting` - Global plugin settings
- `AiHelperProjectSetting` - Project-specific settings
- `AiHelperVectorData` - Vector embeddings for search
- `AiHelperSummaryCache` - Cached AI-generated summaries

## Development Commands

### Testing
```bash
# Setup test environment
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:ai_helper:setup_scm

# Run all tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper
```

### Database
```bash
# Run migrations
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

### Vector Search Setup
```bash
# Generate vector index
bundle exec rake redmine:plugins:ai_helper:vector:generate RAILS_ENV=production

# Register data in vector database
bundle exec rake redmine:plugins:ai_helper:vector:regist RAILS_ENV=production

# Destroy vector data
bundle exec rake redmine:plugins:ai_helper:vector:destroy RAILS_ENV=production
```

## Configuration

### Plugin Configuration
- Main settings managed through `AiHelperSetting` model
- Model profiles configured via `AiHelperModelProfile`
- MCP server config in `config/ai_helper/config.json`
- Langfuse integration config in `config/ai_helper/config.yml`

### Prompt Templates
Agent prompts are stored in YAML files under `assets/prompt_templates/` with support for internationalization (English and Japanese).

## Custom Agent Development

To create custom agents:
1. Inherit from `RedmineAiHelper::BaseAgent` - automatic registration via inheritance hook
2. Create associated tools inheriting from `RedmineAiHelper::BaseTools`
3. Place files anywhere in Redmine and require them - agents are discovered automatically
4. See `example/redmine_fortune/` for a complete example

### MCP Integration
For external tool integration via Model Context Protocol:
1. Configure MCP servers in `config/ai_helper/config.json`
2. System automatically generates SubMcpAgent classes per server
3. Supports both STDIO and HTTP+SSE transport protocols
4. Auto-detects transport type from configuration (no explicit transport field needed)

## Key Files for Development

- `init.rb` - Plugin initialization and registration
- `lib/redmine_ai_helper/` - Core plugin logic
- `app/controllers/ai_helper_controller.rb` - Main chat interface controller with streaming support
- `app/views/ai_helper/` - Chat UI templates and project health reports
- `assets/javascripts/ai_helper.js` - Frontend JavaScript with markdown parsing
- `assets/stylesheets/ai_helper.css` - CSS that integrates with Redmine's design system
- `config/routes.rb` - Plugin routes
- `db/migrate/` - Database migrations showing evolutionary development
- `assets/prompt_templates/` - Internationalized agent prompt templates

## Development Guidelines

### Design Document Adherence
**CRITICAL: Design documents in `specs/` directory are AUTHORITATIVE and MANDATORY.**

- **NEVER deviate from design documents** without explicit user approval
- If a design document exists for the feature you're implementing, follow it exactly
- Design documents specify:
  - Architecture (which classes/modules to use)
  - File locations and naming
  - Method placement and naming
  - API specifications
  - Test file locations
- **DO NOT make "better" architectural decisions** on your own - follow the design
- If you believe the design has issues, **ASK THE USER FIRST** before implementing differently
- When asked "are you following the design?", check the design document thoroughly before answering

### Code Style(Ruby)
- Follow Ruby on Rails conventions
- Write comments in English

### Code Style(Javascript)
- Use `let` and `const` instead of `var`
- Don't use jQuery, use vanilla JavaScript
- Write comments in English

### Frontend Security
- Build HTML structures in ERB templates (`*.html.erb`), not in JavaScript
- This prevents XSS and JS injection vulnerabilities by leveraging Rails' automatic escaping
- JavaScript should only manipulate existing DOM elements rendered by ERB
- Use `sprite_icon` helper for icons, `t()` / `l()` for i18n text in templates

### Error Handling Guidelines
- **NEVER implement fallback error handling** - Fallbacks hide real problems and make debugging impossible
- Let errors surface immediately so they can be properly diagnosed and fixed
- If something is expected to exist (like DOM elements or templates), don't provide fallbacks - fix the root cause instead
- Use proper error logging, but never silently continue with fallback behavior

### Test-Driven Development (TDD)
This project follows Test-Driven Development. **Always write tests BEFORE implementing features.**

#### TDD Workflow
1. **Red**: Write a failing test first that describes the expected behavior
2. **Green**: Write the minimum code necessary to make the test pass
3. **Refactor**: Improve the code while keeping tests green

#### TDD Rules
- **Never write production code without a failing test first**
- When fixing a bug, first write a test that reproduces the bug, then fix it
- When adding a feature, write tests for the feature first, then implement
- Run tests frequently during development to ensure nothing breaks

#### Running Tests
```bash
# Run all plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper

# Run a single test file
bundle exec ruby -I"lib:test" plugins/redmine_ai_helper/test/unit/base_agent_test.rb

# Run tests matching a pattern (using TESTOPTS)
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper TESTOPTS="--name=/test_name_pattern/"
```

#### Testing Guidelines
- Write tests using `shoulda` (context/should blocks), not rspec
- Use `mocha` for mocking - but only when connecting to external servers
- Aim for test coverage of 95% or higher (check `coverage/` directory)
- Test structure:
  - `test/functional/` - Controller tests
  - `test/unit/` - Model, agent, and tool tests
  - `test/integration/` - API and integration tests
- Use `model_factory.rb` for creating test fixtures

## Commit Guidelines
- Do not include any information about Claude Code in commit messages
- Write commit messages in plain English

## Logging Guidelines
- Don't use Rails.logger for logging. Use ai_helper_logger

## CSS Guidelines
- Do not specify custom colors or fonts in CSS. The appearance must be unified with the Redmine interface, so use Redmine's class definitions and CSS as much as possible.
- Use Redmine's standard `.box` class for container elements to maintain visual consistency
- Integrate with Redmine's existing design system rather than creating custom styling

## Installation and Setup

```bash
# Basic installation
cd {REDMINE_ROOT}/plugins/
git clone https://github.com/haru/redmine_ai_helper.git
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# Optional: Vector search setup (requires Qdrant)
bundle exec rake redmine:plugins:ai_helper:vector:generate RAILS_ENV=production
bundle exec rake redmine:plugins:ai_helper:vector:regist RAILS_ENV=production
```

## Architecture Notes

### Dynamic Agent System
- Agents are automatically registered via `BaseAgent.inherited` hook
- SubMcpAgent classes are generated dynamically per MCP server configuration
- Leader agent coordinates complex multi-agent workflows

### Transport Abstraction
- Unified transport layer supporting STDIO and HTTP+SSE protocols
- Auto-detection of transport type from configuration
- Backward compatibility with legacy MCP implementations

### Observability
- Comprehensive Langfuse integration for all LLM providers
- LLM call tracking and monitoring
- Provider-specific wrappers for detailed observability
- Never modify the core Redmine code
