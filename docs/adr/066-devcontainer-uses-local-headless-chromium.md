# ADR-066: Run Playwright MCP against a local headless Chromium in the devcontainer

**Date**: 2026-11-01
**Status**: Accepted

## Context

The devcontainer ran a separate `browserless` container and Playwright MCP
connected to it over CDP (`ws://browserless:3000`). Because `localhost` inside
that container is not the Redmine container, the browser had to reach Redmine
as `app:3000`, while everything else uses `localhost:3000`. This split the
host name used in URLs and cookies, and files for `browser_file_upload` had to
exist on the browser's side, not in the `app` container.

The base image is Debian 13 (trixie) on aarch64. Node.js comes from nvm under
`/workspaces/.nvm`, so it is not available when the Dockerfile runs as root.
Google Chrome has no Linux arm64 build.

## Decision

- Install Debian's `chromium` and `fonts-noto-cjk` in `.devcontainer/Dockerfile`.
- Remove the `browserless` service from `.devcontainer/docker-compose.yml` and
  give `app` `shm_size: 1gb`.
- Start Playwright MCP with `--browser chromium --executable-path
  /usr/bin/chromium --headless --no-sandbox`, pinned to `@playwright/mcp@0.0.84`,
  in `.mcp.json` and `.vscode/mcp.json`.
- Access Redmine at `http://localhost:3000`.

## Consequences

- One host name for Redmine in every tool; uploads use paths in the `app` container.
- No separate browser service to run.
- The image grows by several hundred MB.
- The pinned MCP version must be bumped by hand; Debian's Chromium version
  may drift from what that Playwright release was tested with.
- `--no-sandbox` is needed because the container does not grant the user
  namespaces Chromium's sandbox requires.

## Alternatives Considered

- **Keep browserless**: rejected for the host name split and the file upload limitation.
- **Playwright's bundled Chromium** (`playwright install --with-deps`): rejected
  because Node.js is not available to root during the image build.
- **Google Chrome**: rejected because there is no Linux arm64 build.
