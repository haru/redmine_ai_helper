ARG RUBY_VERSION=3.2
ARG REDMINE_VERSION=master
FROM haru/redmine_devcontainer:${REDMINE_VERSION}-ruby${RUBY_VERSION}
COPY .devcontainer/post-create.sh /post-create.sh
COPY .devcontainer/install-ble.sh /install-ble.sh

RUN gem install ruby-lsp
RUN gem install htmlbeautifier
RUN gem install rubocop
RUN gem install logger
RUN apt-get update && apt-get install -y npm --no-install-recommends
USER vscode
RUN bash -x /install-ble.sh
