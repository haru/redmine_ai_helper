ARG RUBY_VERSION=3.2
ARG REDMINE_VERSION=master
FROM haru/redmine_devcontainer:${REDMINE_VERSION}-ruby${RUBY_VERSION}

COPY .devcontainer/install-ble.sh /install-ble.sh

RUN gem install htmlbeautifier
RUN gem install rubocop
RUN gem install logger

# Install uv (includes uvx) for Serena MCP server
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN bash -x /install-ble.sh


USER vscode
