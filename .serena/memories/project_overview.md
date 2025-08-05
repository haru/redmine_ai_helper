# Redmine AI Helper Plugin - Project Overview

## Purpose
The Redmine AI Helper Plugin adds AI-powered chat functionality to Redmine project management software. It enhances project management efficiency through AI-assisted features including issue search, content summarization, repository analysis, and project health reporting.

## Key Features
- AI chat sidebar integrated into Redmine interface
- Issue search and summarization
- Wiki content processing
- Repository source code analysis and explanation
- Subtask generation from issues
- Project health reports
- Multi-agent architecture with specialized agents for different domains

## Tech Stack
- **Language**: Ruby on Rails (plugin for Redmine)
- **AI/LLM Libraries**: 
  - langchainrb (~> 0.19.5)
  - ruby-openai (~> 8.0.0) 
  - ruby-anthropic (~> 0.4.2)
- **Vector Search**: qdrant-ruby (~> 0.9.9) for Qdrant vector database
- **Observability**: langfuse (~> 0.1.1) for LLM monitoring
- **Testing**: shoulda, factory_bot_rails, simplecov-cobertura
- **Frontend**: Vanilla JavaScript (no jQuery), integrates with Redmine's design system

## Architecture
- Multi-agent system with BaseAgent as foundation
- Automatic agent registration via inheritance hooks
- Specialized agents: LeaderAgent, IssueAgent, RepositoryAgent, WikiAgent, ProjectAgent, McpAgent, etc.
- Model Context Protocol (MCP) integration with STDIO and HTTP+SSE transport
- Vector search with Qdrant for content similarity
- Comprehensive Langfuse integration for observability
- Chat room system for managing conversations and agent coordination