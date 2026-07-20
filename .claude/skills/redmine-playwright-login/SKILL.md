---
name: "redmine-playwright-login"
description: "Connect to the running Redmine instance and log in via the Playwright MCP browser, using REDMINE_PLAYRIGHT_URL/REDMINE_PLAYRIGHT_USER/REDMINE_PLAYRIGHT_PASSWORD environment variables. Use whenever the user asks to open, check, access, or test something in the running Redmine UI (e.g. verifying a feature in the browser, taking a screenshot of a page, manually exercising a flow)."
argument-hint: "Optional: a specific page/path to open after logging in (e.g. '/projects/foo/issues')"
user-invocable: true
disable-model-invocation: false
---

# Redmine Playwright Login

Log in to the currently running Redmine instance through the Playwright MCP browser tools, so the browser session can then be used to inspect pages, verify features, or take screenshots.

## User Input

```text
$ARGUMENTS
```

If a path is given, open it after logging in. Otherwise stop at the post-login page (`/my/page`).

## Procedure

### Step 1: Read the Connection Env Vars

Read these three environment variables (e.g. via `printenv`):

- `REDMINE_PLAYRIGHT_URL` — base URL of the running Redmine instance
- `REDMINE_PLAYRIGHT_USER` — login name
- `REDMINE_PLAYRIGHT_PASSWORD` — password

If any of them is unset or empty, stop and tell the user which one is missing instead of guessing a value.

### Step 2: Navigate to the Login Page

Use `mcp__playwright__browser_navigate` to open `<REDMINE_PLAYRIGHT_URL>/login`.

### Step 3: Inspect the Form

Use `mcp__playwright__browser_snapshot` to get element refs for the `Login` and `Password` textboxes and the `Login` button.

### Step 4: Fill and Submit

Use `mcp__playwright__browser_fill_form` to fill:
- the `Login` textbox with `REDMINE_PLAYRIGHT_USER`
- the `Password` textbox with `REDMINE_PLAYRIGHT_PASSWORD`

Then `mcp__playwright__browser_click` the `Login` button.

### Step 5: Verify

Confirm the resulting page URL is no longer `/login` (typically redirects to `/my/page`). If it's still on `/login`, the snapshot will show a flash error — report the failure to the user rather than retrying blindly.

### Step 6: Optional Navigation

If the user (or `$ARGUMENTS`) specified a page to open next, navigate there now with `mcp__playwright__browser_navigate`.

## Notes

- This is a local/test Redmine instance for development — credentials come from env vars set up for this purpose, not real user secrets.
- Do not print the password anywhere except as needed to pass it into the Playwright fill call.
- Reuse the already-open browser session for subsequent actions in the same conversation — no need to re-login unless the session was closed or logged out.
- Never save screenshots (`mcp__playwright__browser_take_screenshot`) or snapshot files into the plugin's working directory — it's a git repo, and stray files there risk being committed. Always write them under the session scratchpad directory (or another path under `/tmp`) instead.

## Error Handling

- Missing env var: stop and ask the user to set it, don't fall back to a default.
- Login failure (still on `/login` after submit, or an error flash message shown): report the exact error text from the page snapshot to the user.
