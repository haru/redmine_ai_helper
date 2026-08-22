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

Three global identifiers are consumed by `ai_helper.js` (which is out of scope for this refactor). These are preserved as-is:

| Identifier | Defined in ERB | Consumed by (out of scope) |
|---|---|---|
| `window.ai_helper_urls` | `chat/_sidebar.html.erb` | `ai_helper.js`, `ai_helper_markdown_parser.js` |
| `window.getSummary` | `issues/_bottom.html.erb` | `ai_helper.js` |
| `window.getWikiSummary` | `wiki/_summary.html.erb` | `ai_helper.js` |

No new page-scope globals are introduced. If cross-module shared state is needed, it is attached to a single namespace object (e.g., `window.AiHelperCollapsibleFieldset`).

### CSRF token handling

All POST requests continue reading the CSRF token from `meta[name="csrf-token"]`. ERB does not pass the token.

### Conditional rendering

"What to render" and "what config values to pass" remain in ERB (feature flags, permission checks). JS receives the already-filtered config and acts on it.

## Consequences

- **Positive**: All new extractions follow a single, predictable pattern. Element-scoped config avoids naming collisions on pages with multiple instances.
- **Positive**: ERB templates are reduced to data attribution + a single initialization call, making the Ruby↔JS boundary visually obvious.
- **Negative**: The three pre-existing globals cannot be migrated to Pattern A without modifying `ai_helper.js`, which is out of scope. This creates a small inconsistency that must be documented for future maintainers.

## Alternatives Considered

- **Unify everything into `ai_helper_urls`-style page globals**: Rejected. Too broad a scope for per-instance elements (sub-issue rows), effectively creating the same ad-hoc global problem FR-004 prohibits.
- **Introduce Stimulus / data-controller framework**: Rejected. Adding a build/bundle toolchain is explicitly out of scope for this refactor.
- **Meta-tag based config (`meta[name="ai-helper-xxx"]`)**: Rejected. The `data-*` attribute approach is more semantically correct for element-scoped config and aligns with standard HTML patterns.