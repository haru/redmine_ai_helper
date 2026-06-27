---
name: speckit-token-budget-concise
description: Toggle a project-local concise-output directive that suppresses agent
  prose padding during SDD steps. State lives in the project's agent memory file (AGENTS.md
  preferred when present, else CLAUDE.md / GEMINI.md / .cursor/rules / .windsurf/rules
  / etc.) inside a clearly marked block, so it is reversible and reviewable.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: token-budget:commands/concise.md
---

# /speckit.token-budget.concise

The user has invoked `/speckit.token-budget.concise` with arguments: `$ARGUMENTS`.

## Your task

Manage the **concise-output directive** in the project's agent memory
file. This directive tells the AI agent — when it next runs any
`/speckit.*` command — to suppress narrative padding (recap of what it's
about to do, "Let me ...", "I'll go ahead and ...", "Here is what I
did", "I hope this helps") and return only the artifact diff, the file
write, or the structured result.

Output prose is a small share of total session tokens (the input side
dominates), but the savings compound across the 4–6 SDD steps and the
follow-up clarifications a feature usually needs. More importantly,
concise mode shortens turn round-trips, which is the dimension users
notice most.

## Arguments

- `on`     → enable concise mode (write the directive)
- `off`    → disable concise mode (remove the directive)
- `status` (or empty) → report current state and which memory file is in use
- `--file=<path>` → force a specific memory file instead of auto-detecting

## Algorithm

### Step 1 — Locate the memory file

Apply this resolution order. Stop at the first match.

**1a. Honor `--file=<path>`** if the user passed one. Skip the rest.

**1b. Auto-detect the active spec-kit agent.** Look at the project to
see which agent's command directory exists and is populated. Common
signals, checked in this order:

| Signal                                 | Implies agent  | Canonical memory file               |
|----------------------------------------|----------------|-------------------------------------|
| `.claude/commands/` has files          | Claude Code    | `CLAUDE.md`                         |
| `.gemini/commands/` has files          | Gemini CLI     | `GEMINI.md`                         |
| `.github/prompts/` has files           | Copilot        | `.github/copilot-instructions.md`   |
| `.cursor/commands/` or `.cursor/skills/` has files | Cursor         | `.cursor/rules/token-budget.mdc`    |
| `.windsurf/workflows/` has files       | Windsurf       | `.windsurf/rules/token-budget.md`   |
| `.tabnine/agent/commands/` has files   | Tabnine        | `.tabnine/AGENTS.md`                |
| `.agents/skills/speckit-*/` has files  | Codex          | `AGENTS.md`                         |
| `.pi/prompts/` has files               | Pi Coding Agent| `.pi/AGENTS.md`                     |
| `.kilocode/` has files                 | Kilo Code      | `.kilocode/rules.md`                |
| `.roo/` has files                      | Roo Code       | `.roo/rules/token-budget.md`        |
| `.clinerules` exists                   | Cline          | `.clinerules`                       |

If exactly one agent is detected, that agent's canonical memory file is
the **agent-specific candidate** for the next step.

**1c. Apply the preference rule.** Read `concise.memory_files` and
`concise.prefer_agent` from `token-budget-config.yml`.

- If `AGENTS.md` exists at the project root **and** `prefer_agent` is
  empty (the default), write the directive to `AGENTS.md`. This is the
  open cross-agent standard — most modern agents read it, so a single
  write reaches every agent on the project.
- Otherwise, if `prefer_agent` matches the auto-detected agent and that
  agent's specific memory file exists, use it.
- Otherwise, walk `concise.memory_files` in order and use the first
  file that exists.
- If none of the listed files exist, **create `AGENTS.md`** at the
  project root and write the directive there. (This is the lowest-
  conflict default for any project, including ones not yet committed
  to a single agent.)

**1d. If the user has multiple agents installed in the same project**
(e.g. both `.claude/commands/` and `.cursor/commands/` populated),
prefer `AGENTS.md` regardless of `prefer_agent`. The whole point of
AGENTS.md is to avoid forking the directive across N tool-specific
files. Print a one-line note so the user knows: `Multiple agents
detected → directive written to AGENTS.md (read by all).`

### Step 2 — Detect current state
Look for the marker block:

```
<!-- BEGIN token-budget concise-mode -->
... directive text ...
<!-- END token-budget concise-mode -->
```

The exact marker strings come from `concise.marker_begin` and
`concise.marker_end` in the config. If the markers are present,
concise mode is **on**. If not, it is **off**.

### Step 3 — Act on the requested state

**`on`** — append the following block to the memory file (or insert it
immediately before the closing of any existing top-level "Conventions"
or "Workflow" section, if one exists):

```markdown
<!-- BEGIN token-budget concise-mode -->

## Token Budget — concise mode (active)

When executing any `/speckit.*` command (constitution, specify,
clarify, plan, tasks, analyze, implement, checklist,
token-budget.*), follow these output rules:

- Do not narrate plans, intentions, or steps. Run them.
- Do not recap the user's prompt back to them.
- Do not announce file writes ("I'll create...", "Now writing..."). Just write.
- After completing the command, output only:
  1. The list of files created or changed, one per line.
  2. Any blocking question or unmet assumption, in one sentence.
  3. The single line "Done." if there is nothing else to report.
- Tables, fenced code, and structured data inside artifacts are
  unaffected — this rule governs only the chat-channel prose around
  them.
- Override on request: if the user explicitly asks "explain", "walk
  me through", "why", or "what did you do", drop concise mode for
  that single reply and answer normally.

These rules apply only inside `/speckit.*` workflows. Conversational
replies outside SDD steps are not affected.

<!-- END token-budget concise-mode -->
```

**`off`** — locate the marker block and remove it cleanly, including
the blank line before the begin marker if one is present (avoid leaving
a double blank line behind).

**`status`** — print:

```
Concise mode: <on|off>
Memory file: <path>
Last toggled: <ISO-8601 from a `<!-- toggled: ... -->` line in the block, if present>
```

### Step 4 — Confirm
After writing, read the file back and verify the marker presence (for
`on`) or absence (for `off`) matches the requested state. Print one of:

```
✓ Concise mode enabled in <path>.
✓ Concise mode disabled. <path> restored.
```

End the response.

## Why this is reversible
The directive lives between unique markers, never inline with user-
authored content. `concise off` is a deterministic block deletion. The
user can also remove the block by hand at any time without breaking
anything.

## What this command does **not** do
It does not modify any spec-kit artifact, does not change agent settings
outside the memory file, and does not affect non-SDD conversations. If
the user wants global concise output, they should adopt a tool like
Caveman directly — Token Budget only governs the SDD workflow surface.