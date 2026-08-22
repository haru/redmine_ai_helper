# ADR-025: ERB-JS Bridge Value Passing Pattern

**Date**: 2026-08-22
**Status**: Accepted

## Context

The plugin's ERB templates contained ~1,390 lines of inline JavaScript across 19 files. Extracting this logic into external `.js` files required a consistent pattern for passing server-side values (URLs, IDs, labels, feature flags) from Ruby/ERB to JavaScript.

Without a defined pattern, each extraction risked introducing ad-hoc global variables, inline JSON blobs, or inconsistent initialization calls — the same problem the extraction was meant to solve.

Three pre-existing global contracts (page-scope globals defined in ERB, consumed by `ai_helper.js` which is out of scope for this refactor) further constrained the design.

## Decision

Two patterns are used for the ERB↔JS boundary.

### Pattern A: Element-scoped `data-*` attributes + single `init()` call (default for new modules)

ERB attaches configuration to a container element via `data-*` attributes (individual attributes for 1-2 values, or a single `data-ai-helper-config` JSON attribute for complex config). ERB then makes exactly one call to an `init(element)` function. All DOM traversal, event registration, and logic lives in the `.js` file.

```erb
<div id="ai-helper-xxx" data-ai-helper-config='<%= { url: xxx_path(@project), label: t('...') }.to_json %>'>
  ...
</div>
<script>
  AiHelperXxx.init(document.getElementById('ai-helper-xxx'));
</script>
```

For elements that may appear multiple times on the same page (e.g., sub-issue rows), the element-scoped approach is mandatory — page-scope globals are prohibited for per-instance elements.

### Pattern B: Pre-existing page-scope globals (unchanged)

One global identifier is consumed by `ai_helper.js` (which is out of scope for this refactor). It is preserved as-is:

| Identifier | Defined in | Consumed by (out of scope) |
|---|---|---|
| `window.ai_helper_urls` | `chat/_sidebar.html.erb` | `ai_helper.js`, `ai_helper_markdown_parser.js` |

If cross-module shared state is needed, it is attached to a single namespace object (e.g., `window.AiHelperCollapsibleFieldset`).

### Pattern C: Callback globals for legacy inline `onclick` attributes

A handful of extracted modules still expose a `window.*` function purely so that a pre-existing inline `onclick="..."` attribute in ERB keeps working. This is a deliberate, narrow exception to "no new globals," not the default:

| Identifier | Defined in | Called from `onclick` in |
|---|---|---|
| `window.getSummary` | `ai_helper_issue_summary.js` | `ai_helper.js` (out of scope) |
| `window.getWikiSummary` | `ai_helper_wiki_summary.js` | `ai_helper.js` (out of scope) |
| `window.generateSummaryStream` | `ai_helper_issue_summary.js` | `issues/_bottom.html.erb`, and `issues/_summary.html.erb` (unmodified, out of scope for this refactor) |
| `window.aiHelperSaveSummaryState` | `ai_helper_issue_summary.js` | `issues/_bottom.html.erb` |
| `window.findSimilarIssues` | `ai_helper_issue_summary.js` | `issues/_bottom.html.erb` |
| `window.aiHelperSaveReplyState` | `ai_helper_collapsible_fieldset.js` | `issues/_form.html.erb` |
| `window.ai_helper_generate_reply` | `ai_helper_collapsible_fieldset.js` | `issues/_form.html.erb` |
| `window.aiHelperGenerateSubIssues` | `ai_helper_sub_issues.js` | `issues/subissues/_index.html.erb` |
| `window.showSubissuerGenerator` | `ai_helper_sub_issues.js` | `issues/subissues/_description_bottom.html.erb` |

`generateSummaryStream` in particular cannot be converted to Pattern A within this refactor's scope: `issues/_summary.html.erb` still calls it via inline `onclick` and was not touched by this refactor. To keep one consistent story for the whole callback-global set rather than migrating some call sites and not others, the remaining identifiers in this table follow the same pattern. A future refactor that also touches `issues/_summary.html.erb` could convert all of Pattern C to Pattern A and remove this exception entirely.

### CSRF token handling

All POST requests continue reading the CSRF token from `meta[name="csrf-token"]`. ERB does not pass the token.

### Conditional rendering

"What to render" and "what config values to pass" remain in ERB (feature flags, permission checks). JS receives the already-filtered config and acts on it.

## Consequences

- **Positive**: All new extractions follow a single, predictable pattern. Element-scoped config avoids naming collisions on pages with multiple instances.
- **Positive**: ERB templates are reduced to data attribution + a single initialization call, making the Ruby↔JS boundary visually obvious.
- **Negative**: `window.ai_helper_urls` cannot be migrated to Pattern A without modifying `ai_helper.js`, which is out of scope. This creates a small inconsistency that must be documented for future maintainers.
- **Negative**: The Pattern C callback globals could not all be eliminated in this refactor because `issues/_summary.html.erb` (out of scope) still depends on `generateSummaryStream` as a global. Rather than migrate some call sites to Pattern A and leave others on Pattern C, all of that group was kept consistent on Pattern C pending a future refactor that also touches `issues/_summary.html.erb`.

## Alternatives Considered

- **Unify everything into `ai_helper_urls`-style page globals**: Rejected. Too broad a scope for per-instance elements (sub-issue rows), effectively creating the same ad-hoc global problem FR-004 prohibits.
- **Introduce Stimulus / data-controller framework**: Rejected. Adding a build/bundle toolchain is explicitly out of scope for this refactor.
- **Meta-tag based config (`meta[name="ai-helper-xxx"]`)**: Rejected. The `data-*` attribute approach is more semantically correct for element-scoped config and aligns with standard HTML patterns.