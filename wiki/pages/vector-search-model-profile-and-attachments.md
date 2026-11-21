---
title: Vector Model Profile & Attachments in the Index
type: reference
sources: [S002, S004, S010, S012, S033]
updated: 2026-11-21
---

# Vector Model Profile & Attachments in the Index

The optional vector model profile and attachment indexing. Split from [Vector Search](./vector-search.md).

## Vector model profile

An optional separate profile for the embedding **and** summarization work done
during index registration and search (S004). Configured on the global
`AiHelperSetting` via two added fields: `use_vector_model_profile` (boolean,
default `false`) and `vector_model_profile_id` (optional FK to an
`AiHelperModelProfile`) (S004). Existing rows migrate to
`use_vector_model_profile = false, vector_model_profile_id = nil`, so existing
users are unaffected (S004).

UI rules (S004):

- The "Select a vector-search model profile" checkbox sits under "Enable vector
  search" and is **hidden** while vector search is off.
- The profile dropdown shows only when the checkbox is on.
- Checkbox on + no profile selected → **validation error** on save.
- Unchecking and saving **clears `vector_model_profile_id` to nil** (the ID is
  not retained).

**Fallback behavior (contrast with the think model)**: when no vector profile is
set — checkbox off, *or* `use_vector_model_profile` is on but `vector_model_profile_id` is blank — vector processing **silently falls back** to the normal LLM
profile and continues without error (S004). If the referenced profile is missing,
it is surfaced similarly to the
[Think Model](./think-model.md), where a missing/invalid profile is surfaced as
an error rather than falling back.

## Attachments in the index

When [multi-modal file support](./multi-modal-file-support.md) is enabled,
attachment contents are analyzed and folded into the vector index during
registration and similar-issue search, improving similarity matching for issues
carrying meaningful attachments (S002).

By default **every** module-enabled project is indexed; a "Register all
projects" toggle lets an admin pick specific projects instead, which also gates
where vector-dependent search works (S012). An admin can also widen the base
set itself to **all** projects (module-enabled or not) via the [all-projects
data-access scope](./all-projects-data-access-scope.md) setting — the
"Register all projects" / selection behavior then applies on top of that
wider set. See [All-Projects Scope: Effects &
Alternatives](./all-projects-scope-effects.md) for that mechanism (S033). See
[Vector Search Internals](./vector-search-internals.md) for that selection model,
indexing, payload indexes, sync, and `ensure_indexes` (S010, S012).

## Related

- [Vector Search](./vector-search.md) — the main page.
