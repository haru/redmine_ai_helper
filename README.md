# Redmine AI Helper Plugin

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![build](https://github.com/haru/redmine_ai_helper/actions/workflows/build.yml/badge.svg)](https://github.com/haru/redmine_ai_helper/actions/workflows/build.yml)
[![Maintainability](https://qlty.sh/badges/a0cabed6-3c2d-4eb2-a7b0-2cd58e6fdf72/maintainability.svg)](https://qlty.sh/gh/haru/projects/redmine_ai_helper)
[![codecov](https://codecov.io/gh/haru/redmine_ai_helper/graph/badge.svg?token=1HOSGRHVM9)](https://codecov.io/gh/haru/redmine_ai_helper)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/haru/redmine_ai_helper)
![Redmine](https://img.shields.io/badge/redmine-6.0-blue?logo=redmine&logoColor=%23B32024&labelColor=f0f0f0&link=https%3A%2F%2Fwww.redmine.org)


- [Redmine AI Helper Plugin](#redmine-ai-helper-plugin)
- [✨ Features](#-features)
  - [Chat Interface](#chat-interface)
  - [Issue Summarization](#issue-summarization)
  - [Create a comment draft with AI Helper](#create-a-comment-draft-with-ai-helper)
  - [Generate subtasks from issues](#generate-subtasks-from-issues)
- [📦 Installation](#-installation)
- [⚙️ Basic Configuration](#️-basic-configuration)
  - [Plugin Settings](#plugin-settings)
  - [Role and Permission Settings](#role-and-permission-settings)
  - [Project-specific Settings](#project-specific-settings)
- [⚙️ Advanced Configuration](#️-advanced-configuration)
  - [MCP Server Settings](#mcp-server-settings)
  - [Vector Search Settings](#vector-search-settings)
    - [Qdrant Setup](#qdrant-setup)
    - [Creating the Index](#creating-the-index)
    - [Recreating the Index](#recreating-the-index)
- [🛠️ Build your own Agent](#️-build-your-own-agent)
- [🪄 Langfuse integration](#-langfuse-integration)
- [⚠️ Important Notice](#️-important-notice)
- [🤝 Contributing](#-contributing)
  - [How to Run Tests](#how-to-run-tests)
    - [Preparation](#preparation)
    - [Running the Tests](#running-the-tests)
- [🐞 Support](#-support)
- [🌟 Credits](#-credits)

The Redmine AI Helper Plugin adds AI chat functionality to Redmine, enhancing project management efficiency through AI-powered support.

# ✨ Features

- Adds an AI chat sidebar to the right side of your Redmine interface
- Enables various AI-assisted features including:
  - Issue search
  - Issue and Wiki content summarization
  - Repository source code explanation
  - Generate subtasks from issues
  - Other project and Redmine-related inquiries
- Provides a project health report
- Supports multiple AI models and services
- MCP server integration
- Vector search using Qdrant

## Chat Interface

The AI Helper Plugin provides a chat interface that allows you to interact with AI models directly within Redmine. You can ask questions, get explanations, and receive assistance with project-related tasks.

![Image](https://github.com/user-attachments/assets/150259a0-4154-43e5-8e2b-bc75c1365cd8)

## Issue Summarization

Issue summarization allows you to generate concise summaries of issues pages.

![Image](https://github.com/user-attachments/assets/2c62a792-b746-46ce-9268-3e29bdb4e53d)

## Create a comment draft with AI Helper

You can create a comment draft for an issue using the AI Helper Plugin. This feature allows you to generate a comment based on the issue's content, which you can then edit and post.

![Image](https://github.com/user-attachments/assets/89f58bb4-bbc9-4407-9c55-309fac6893c2)

## Generate subtasks from issues

You can generate subtasks from issues using the AI Helper Plugin. This feature allows you to create detailed subtasks based on the content of an issue, helping you break down complex tasks into manageable parts.

![Image](https://github.com/user-attachments/assets/c91a8d96-b608-43f2-9461-a0bdf8b35936)

## Similar Issues Search

You can search for similar issues using the AI Helper Plugin. This feature is only available if vector search is set up. The AI Helper Plugin allows you to find issues similar to the current one based on its content, making it easier to discover related past issues and solutions.

![Image](https://github.com/user-attachments/assets/3217149b-4874-49b9-aa98-b35a7324bca3)

## Project Health Report

You can generate a project health report using the AI Helper Plugin. This feature provides a comprehensive overview of the project's status, including metrics such as open issues, closed issues, and overall project health.

![Image](https://github.com/user-attachments/assets/8f01c6ef-6cee-4e79-b693-c17081566c78)

Helth report can be exported to Markdown and PDF formats.

# 📦 Installation

1. Extract the plugin to your Redmine plugins folder:
   ```bash
   cd {REDMINE_ROOT}/plugins/
   git clone https://github.com/haru/redmine_ai_helper.git
   ```

2. Install required dependencies:
   ```bash
   bundle install
   ```

3. Run database migrations:
   ```bash
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

4. Restart Redmine:


# ⚙️ Basic Configuration

## Plugin Settings

1. Open the AI Helper settings page from the Administration menu.
2. Create a model profile and fill in the following fields:
   - Type: Choose the AI model type (e.g., OpenAI, Anthropic. Strongly recommend using OpenAI or Anthropic)
   - Name: Enter a name for the model profile
   - Access Key: Enter the API key for the AI service
   - Model name: Specify the AI model name (e.g., gpt-4.1-mini)
   - Temperature: Set the temperature for the AI model (e.g., 0.7)
3. Select the model profile you created from the dropdown menu and save the settings.


## Role and Permission Settings

1. Go to "Roles and permissions" in the administration menu
2. Configure the AI Helper permissions for each role as needed

## Project-specific Settings

1. Open the settings page for each project where you want to use the plugin
2. Go to the "Modules" tab
3. Enable "AI Helper" by checking the box
4. Click "Save" to apply the changes

# ⚙️ Advanced Configuration

## MCP Server Settings

The "Model Context Protocol (MCP)" is an open standard protocol proposed by Anthropic that allows AI models to interact with external systems such as files, databases, tools, and APIs.
Reference: https://github.com/modelcontextprotocol/servers

The AI Helper Plugin can use the MCP Server to perform tasks, such as sending issue summaries to Slack.

1. Create `config/ai_helper/config.json` under the root directory of Redmine.
2. Configure the MCP server as follows (example for Slack, GitHub, and Context7):
   ```json
   {
      "mcpServers": {
         "slack": {
            "type": "stdio",
            "command": "npx",
            "args": [
               "-y",
               "@modelcontextprotocol/server-slack"
            ],
            "env": {
               "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
               "SLACK_TEAM_ID": "T01234567"
            }
         },
         "github": {
            "type": "http",
            "url": "https://api.githubcopilot.com/mcp/",
            "headers": {
               "Authorization": "Bearer github_pat_xxxxxxxxxxxxxxx"
            }
         },
         "context7": {
            "type": "sse",
            "url": "https://mcp.context7.com/sse"
         }
      }
   }
   ```
3. Restart Redmine.

## Vector Search Settings

Configure settings to perform vector searches for issues using Qdrant.
With this configuration, the AI Helper Plugin can use Qdrant to perform vector searches on Redmine issues and wiki data.

**Note:** Vector search functionality is not available when using Anthropic AI models. Please use OpenAI or other supported AI providers for vector search features.

### Qdrant Setup

Here is an example configuration using Docker Compose.

```yaml:docker-compose.yml
services:
   qdrant:
      image: qdrant/qdrant
      ports:
         - 6333:6333
      volumes:
         - ./storage:/qdrant/storage
```

### Creating the Index

Run the following command to create the index.

```bash
bundle exec rake redmine:plugins:ai_helper:vector:generate RAILS_ENV=production
```

Registers ticket data into the index. The initial run may take some time.

```bash
bundle exec rake redmine:plugins:ai_helper:vector:regist RAILS_ENV=production
```

Please execute the above commands periodically using cron or a similar tool to reflect ticket updates.

This completes the configuration.

### Recreating the Index

If you change the embedding model, delete the index and recreate it using the following commands.

```bash
bundle exec rake redmine:plugins:ai_helper:vector:destroy RAILS_ENV=production
```

# 🛠️ Build your own Agent

The AI Helper plugin adopts a multi-agent model. You can create your own agent and integrate it into the AI Helper plugin.

To create your own agent, you need to create the following two files:

- **Agent Implementation**
   - A class that inherits from `RedmineAiHelper::BaseAgent`
   - Defines the agent's behavior
- **Tools**
   - A class that inherits from `RedmineAiHelper::BaseTools`
   - Implements the tools used by the agent

Place these files in any location within Redmine and load them.

As an example, there is a plugin called `redmine_fortune` under the `example` directory. Place this plugin in the `plugins` folder of Redmine. This will add a fortune-telling feature to the AI Helper plugin. When you ask, "Tell me my fortune for today," it will return a fortune-telling result.

# 🪄 Langfuse integration
By integrating with Langfuse, you can track the usage of the AI Helper Plugin. This allows you to monitor the cost of LLM queries and improve prompts effectively.


![Image](https://github.com/user-attachments/assets/35904911-db39-4da7-baf6-a90fe05d9115)

To configure the integration, add the following to `{REDMINE_ROOT}/config/ai_helper/config.yml`:

```yaml
langfuse:
  public_key: "pk-lf-************"
  secret_key: "sk-lf-************"
  endpoint: https://us.cloud.langfuse.com # Change this to match your environment
```

# ⚠️ Important Notice

Please note that AI responses may not always be 100% accurate. Users should verify and validate AI-provided information at their own discretion.


# 🤝 Contributing

I welcome bug reports and feature improvement suggestions through GitHub Issues. Pull requests are also appreciated.

⚠️ When creating a pull request, always branch off from the `develop` branch.

Please make sure that all tests pass before pushing.

## How to Run Tests

### Preparation

Create a test database.

```bash
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
```

Create a test Git repository.

```bash
bundle exec rake redmine:plugins:ai_helper:setup_scm
```

### Running the Tests

```bash
bundle exec rake redmine:plugins:test NAME=redmine_ai_helper
```

# 🐞 Support

If you encounter any issues or have questions, please open an issue on GitHub.


# 🌟 Credits

Developed and maintained by [Haru Iida](https://github.com/haru).
