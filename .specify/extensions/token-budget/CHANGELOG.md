## 1.0.1 (2026-05-23)

### 🩹 Fixes

- remove command aliases to reduce skill count ([798bfcf](https://github.com/tinesoft/spec-kit-token-budget/commit/798bfcf))
- **config:** ship `token-budget-config.yml` so it is present after install ([4fa6752](https://github.com/tinesoft/spec-kit-token-budget/commit/4fa6752))
- **hooks:** add missing description field to all hook entries ([6ab70a6](https://github.com/tinesoft/spec-kit-token-budget/commit/6ab70a6))

### ❤️ Thank You

- Tine Kondo @tinesoft

# 1.0.0 (2026-05-10)

### Features

- `/speckit.token-budget.compact` — in-place SDD artifact compaction with three levels (light, medium, aggressive). Lossless on requirements, decisions, contracts, IDs. Backs originals up as `<artifact>.full.md`. Aliases: `compress`, `distill`.
- `/speckit.token-budget.scope` — pre-flight reading manifest for the next workflow phase, with token budget enforcement. Aliases: `brief`, `focus`.
- `/speckit.token-budget.concise` — toggle a marker-bracketed concise-output directive in the project's agent memory file. Auto-detects the active spec-kit agent, prefers `AGENTS.md` (open cross-agent standard) when present. Covers every agent in spec-kit's `INTEGRATION_REGISTRY` (Claude Code, Cursor, Copilot, Gemini CLI, Windsurf, Cline, Roo Code, Kilo Code, Aider, Codex CLI, Tabnine, Pi Coding Agent). Aliases: `terse`, `quiet`.
- `/speckit.token-budget.usage` — per-artifact token dashboard with projected per-phase budgets and warranted recommendations. Aliases: `stats`, `report`.
- `scripts/bash/slim_output.sh` — RTK-style CLI output compressor with built-in rules for git_status, git_log, pytest, npm_test, plus a generic head_tail fallback. Defers to real `rtk` if installed.
- `scripts/bash/estimate_tokens.sh` — fast token estimator using tiktoken (cl100k_base) when available, chars/4 heuristic otherwise.
- `scripts/bash/compact_helper.sh` — backup, snapshot, summarize, and stamp bookkeeping for `compact`.
- PowerShell mirrors of `estimate_tokens` and `compact_helper`.
- Hooks: `before_plan`, `before_tasks`, `before_implement` (auto-scope); `after_specify`, `after_plan`, `after_tasks` (auto-compact). All optional.
- `token-budget-config.template.yml` with full per-knob documentation.
