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

RUN bash -x /install-ble.sh
RUN (type -p wget >/dev/null || ( apt-get update &&  apt-get install wget -y)) \
    &&  mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out |  tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    &&  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |  tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    &&  apt-get update \
    &&  apt-get install gh -y

USER vscode