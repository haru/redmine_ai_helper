---
title: Testing Classic Scripts via Dynamic Import
type: decision
sources: [S024]
updated: 2026-08-22
---

# Testing Classic Scripts via Dynamic Import

## Constraint

The 12 files under `assets/javascripts/` load via `javascript_include_tag` as
plain browser scripts, outside any module system. The feature must not
require a build step or change this loading, so `export`/`import` can never
be added to production code (S024).

## Decision

Tests load a target file with a **side-effect-only dynamic `import()`**. A
file with no `import`/`export` statements is still a syntactically valid ES
module — it can be evaluated and its side effects run. Because Vitest passes
imported files through its transform pipeline, `@vitest/coverage-v8`
instruments them; reading the source and `eval`-ing it in jsdom's `window`
would skip that instrumentation entirely, which was the deciding factor
(S024).

- `vi.resetModules()` runs before each dynamic import, discarding the
  previous test's module-cache entry so the file's top-level code re-executes
  from a clean state — this is what makes execution-order independence
  possible.
- jsdom makes `window` the global object itself, so a file's own
  `window.X = ...` assignments work unchanged, with no jsdom-specific glue.
- Files that initialize on `DOMContentLoaded` (`ai_helper_project_health.js`
  and 3 others) need the test to manually dispatch
  `document.dispatchEvent(new Event('DOMContentLoaded'))` after import,
  because jsdom's `readyState` is already `complete` by the time the script
  loads (S024).

## Production-code changes: additive only

Once evaluated as an ES module, a top-level `class X {}` becomes
module-scoped and no longer lands on `window` automatically — tests can only
reach it if the file already publishes it. Of the 12 target files, only 4
needed a new trailing line to keep exposing their global:
`ai_helper_assignment_suggestion.js`, `ai_helper_auto_completion.js`,
`ai_helper_chat_settings.js`, and `ai_helper.js`. The other 8 already exposed
what they needed (S024).

`ai_helper.js`'s one `var` (line 934, `var ai_helper = new AiHelper();`)
became:

```js
window.AiHelper = AiHelper;
window.ai_helper = new AiHelper();
```

ERB inline handlers (e.g. `onclick="ai_helper.fold_chat(true)"` in
`_sidebar.html.erb`) reference `ai_helper` as a bare identifier, which
resolves through the scope chain up to the global object. `var` was creating
that global-object property, which is what made the bare reference work.
Switching to `const` would have kept the bare-identifier resolution but
broken any `window.ai_helper`-qualified reference — none were found, but
scripts evaluated dynamically via `innerHTMLwithScripts` could plausibly use
that form. `window.ai_helper = ...` resolves identically to the original
`var` from both a bare identifier and `window.ai_helper` (S024).

## Rejected alternatives

- **Read the source and `eval` it in jsdom's `window`**: no production-code
  changes needed, but drops out of `@vitest/coverage-v8`'s instrumentation —
  the coverage requirements can't be met this way.
- **UMD-style export branch at the end of each file**: adds a test-only
  branch to production code — the kind of shim the project's simplicity rule
  forbids.
- **Full migration to ES modules loaded via `type="module"`**: out of scope,
  and risks breaking the load-order coordination the current classic-script
  setup depends on (S024).

## Residual risk

ES modules always evaluate in strict mode. A classic script that depended on
sloppy-mode behavior — most plausibly, assignment to an undeclared variable —
could behave differently once loaded this way. `no-undef` catches that case
first, so the working order is lint-clean before tests are written for a
given file (S024).

## Related

- [JavaScript Quality Tooling](./js-quality-tooling.md)
- [Browser-Side JavaScript Tests](./js-test-convention.md)
