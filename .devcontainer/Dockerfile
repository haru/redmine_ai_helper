ARG RUBY_VERSION=3.2
ARG REDMINE_VERSION=master
FROM haru/redmine_devcontainer:${REDMINE_VERSION}-ruby${RUBY_VERSION}

COPY .devcontainer/install-ble.sh /install-ble.sh

RUN gem install htmlbeautifier
RUN gem install rubocop
RUN gem install logger

# Install MySQL client
RUN apt-get update && apt-get install -y default-mysql-client && rm -rf /var/lib/apt/lists/*

# Install Chromium (headless browser for Playwright MCP) and CJK fonts.
# Playwright MCP launches /usr/bin/chromium directly, so Redmine is reached at localhost:3000.
RUN apt-get update && apt-get install -y chromium fonts-noto-cjk && rm -rf /var/lib/apt/lists/*

# Install uv (includes uvx) for Serena MCP server
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN bash -x /install-ble.sh


USER vscode

RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://opencode.ai/install | bash
RUN curl https://qlty.sh | sh
RUN gem install lefthook
