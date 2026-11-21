---
title: JavaScript ESLint Configuration
type: component
sources: [S024]
updated: 2026-11-21
---

# JavaScript ESLint Configuration

The ESLint flat config rules. Split from [JavaScript Quality Tooling](./js-quality-tooling.md).

## ESLint configuration

One `eslint.config.js` at the repo root, with separate rule sets for
`assets/javascripts/**` and `test/javascript/**`. The production rule set
maps directly to what static analysis must catch: `no-undef` (undefined
references), `no-unused-vars`, `no-var` (explicit `error` — not in
`recommended`), `no-unreachable`, `no-constant-condition` and
`no-constant-binary-expression`, plus parse errors reported automatically
(S024).

Browser/plugin globals are declared explicitly in
`languageOptions.globals` — `globals.browser` plus a short enumerated list,
rather than turning `globals` off (too many false positives from
Redmine/browser globals) or leaving it wide open (misses real typos):

- ERB-supplied, referenced as bare identifiers: `ai_helper_urls`,
  `getSummary`, `getWikiSummary`, `ai_helper`
- `AiHelperMarkdownParser`, assigned via `window.AiHelperMarkdownParser =
  class {...}` (no local declaration), then referenced as a bare identifier
  from other files

Most other cross-file names — shared classes (`AiHelperTypoChecker`,
`AiHelperMasterDetail`, `AiHelperAutoCompletion`,
`AiHelperAssignmentSuggestion`, `CommandCompletion`, `AiHelper`), reload
guards (`aiHelperComparisonInitialized`, `aiHelperProjectHealthInitialized`,
`aiHelperProjectHealthLoaded`, `aiHelperStuffTodoInitialized`,
`aiHelperInstances`), and cross-file functions (`updateComparisonButton`,
`updateHealthReportHistory`) — do **not** need a globals entry: each is
declared locally in its own file (`class X {...}` or `function f() {...}`)
and every other file accesses it through an explicit `window.X` property
read, never as a bare identifier, so `no-undef` never flags it. The
alternative — a `/* global ... */` comment per file — was rejected for the
few names that *do* need declaring: it scatters lint-only comments across
production files and loses the whole-picture view this short list gives
(S024).

Biome and JSHint/StandardJS were considered for lint and rejected: Biome's
global-resolution equivalent to `no-undef` is weak for classic (non-module)
scripts; JSHint/StandardJS can't express per-directory rule sets, which the
production/test split above needs (S024).

## Related

- [JavaScript Quality Tooling](./js-quality-tooling.md) — the main page.
