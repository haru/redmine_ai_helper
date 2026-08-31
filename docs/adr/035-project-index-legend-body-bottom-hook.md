# ADR-035: Add the AI Helper legend entry via view_layouts_base_body_bottom + JS relocation

**Date**: 2026-08-31
**Status**: Accepted

## Context

`app/views/projects/index.html.erb` (Redmine core) renders a legend at the bottom of the
logged-in project list, explaining the "My projects" and "Bookmarked" icons shown next to
project names:

```erb
<% if User.current.logged? %>
<p style="text-align:right;">
<span class="icon icon-user my-project">...</span>
<span class="icon icon-bookmarked-project">...</span>
</p>
<% end %>
```

Feature 055 adds an AI Helper icon to the project list (both board and list display types) and
needs to explain that icon in the same legend, for both display types, without touching list
rendering. Unlike most extension points this plugin uses (`view_issues_show_details_bottom`,
`view_projects_show_right`, etc.), Redmine core does not call any `Redmine::Hook` hook at this
exact location in `index.html.erb`, so there is no `render_on` target that lands HTML directly
inside that `<p>`.

Constitution IV requires that HTML be generated server-side (ERB), and that JavaScript be
limited to manipulating DOM elements ERB has already rendered — it must not assemble icon or
label markup itself.

## Decision

Register a new partial, `ai_helper/project/_index_legend`, on the existing
`view_layouts_base_body_bottom` hook (already used by this plugin for `wiki/textarea_overlay`
and `shared/stuff_todo_modal_wrapper`, so it is a proven extension point). The partial:

- Renders a `<span id="ai-helper-index-legend-item" hidden>` containing the same
  `sprite_icon('ai-helper-robot', ...)` markup used for the in-list icon, only when
  `controller_name == 'projects' && action_name == 'index' && User.current.logged?`.
- Emits nothing otherwise (unauthenticated users, or any other controller/action).
- Also includes `ai_helper_project_legend.js` under the same condition, so the script is only
  loaded on the one page it applies to.

`assets/javascripts/project_legend/ai_helper_project_legend.js` runs on `DOMContentLoaded` and:

- Looks up the hidden `#ai-helper-index-legend-item` span and the existing legend `<p>` via
  `document.querySelector('.icon-bookmarked-project')`'s parent.
- If both exist, un-hides the span and appends it as a child of the existing legend `<p>`
  (`Node.appendChild` moves an existing node — it does not clone or recreate it), leaving the
  "My projects" and "Bookmarked" spans untouched.
- If either is missing, does nothing — no error, no legend added.

This way, all icon/label HTML is server-generated up front; the script only relocates and shows
an element that already exists in the DOM.

## Consequences

**Positive**:
- Satisfies Constitution IV: no HTML string assembly happens in JavaScript.
- Reuses an already-integrated hook point (`view_layouts_base_body_bottom`) rather than adding a
  new one.
- Degrades safely: `#ai-helper-index-legend-item` and the legend `<p>` are each independently
  optional in the DOM, so logged-out users, `projects#index` when the legend `<p>` itself is
  absent, and any other controller/action are all no-ops.
- Board and list display types share the same `index.html.erb` legend markup, so one hook
  partial covers both (FR-005) without a `display_type` branch.

**Negative**:
- The legend now depends on a `document.querySelector('.icon-bookmarked-project')` DOM lookup
  succeeding at `DOMContentLoaded` time; if a future Redmine core release restructures or removes
  that legend `<p>`, the AI Helper legend entry would silently stop appearing (no error, but also
  no explanation of the AI Helper icon) until this partial/script pair is updated to match.
- Introduces one more small, page-scoped JS file to maintain, versus a purely server-side
  solution.

## Alternatives Considered

- **Fully override `app/views/projects/index.html.erb` via `prepend_view_path`**: Would let the
  legend `<p>` be edited directly in ERB with no JS involved, but requires shadowing the entire
  core view. Any future Redmine core change to `index.html.erb` (columns, filters, other legend
  items) would need to be manually re-applied to the override, and it risks conflicting with
  other plugins that shadow the same view. Rejected as disproportionate maintenance cost for one
  legend entry.
- **Assemble the icon/label HTML directly in JavaScript**: Simpler (no server round trip
  needed for the fragment), but violates Constitution IV, which requires HTML to be built in ERB
  so `sprite_icon`/`l()` (i18n, icon assets) stay the single source of truth.
- **Add a controller filter on `ProjectsController#index` that sets an instance variable, then
  edit the core view to check it**: Still requires shadowing the core view to read the new
  instance variable, with the same maintenance cost as full override, plus a new controller-level
  patch. Rejected as broader surface area for no benefit over the hook + JS approach.
