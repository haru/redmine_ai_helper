# Optional Redmine DMSF integration (experimental)

The `DmsfAgent` and `DmsfTools` provider offer an initial read-only bridge between
AI Helper chat and [Redmine DMSF](https://github.com/picman/redmine_dmsf).
No external MCP service, database migration, or changes to DMSF are required.

## Requirements and activation

- Redmine DMSF installed and loaded, with the **DMSF** module enabled for the target project.
- AI Helper enabled for the project, except where AI Helper's **Target all projects** setting allows cross-project access.
- The requester needs DMSF's `view_dmsf_files` permission. Document analysis additionally requires `view_dmsf_file_revisions`.
- Set **`REDMINE_AI_HELPER_DMSF_ENABLED=1`** in the Redmine process environment (default: disabled).
- Enable **Administration → AI Helper → Send attachments to LLM**. This is the existing
  global opt-in; both this and the dedicated environment toggle are required for discovery.
- The maximum DMSF file size is the existing **attachment_max_size_mb** value (default 3 MB).

The agent is hidden automatically when DMSF is not installed or either opt-in
is off. All tool invocations re-check authorization independently, even
when invoked outside the chat through another interface.

## Current commands

- `search_files(query:, project_id: nil, limit: 10)` searches filename, title,
  and description. When DMSF's full-text index (Xapian) is available, matches
  inside document **content** are included too. Results include project, folder
  path, current version/revision and a DMSF view link. Up to 20 results are
  returned; at most 2,000 documents are scanned per request. `truncated: true`
  indicates that the result/scan cap was reached. Content matches are
  re-authorized per hit and only appear when `RedmineDmsf.xapian_available` is
  true (the `xapian` gem and a built index); otherwise search is metadata-only.
- `analyze_file(file_id:, question: nil)` analyzes the **current revision** of a
  PDF or UTF-8 plain text/code document, through the configured AI model. The
  document bytes are sent to the AI provider only after access checks and the
  explicit attachment opt-in. Bytes are carried as an in-memory attachment and
  never returned to the calling agent or embedded as a filesystem path.

## Limitations and follow-up work

- **Content-wide search depends on DMSF Xapian.** Text inside documents is
  found only when DMSF's Xapian index is installed and built
  (`RedmineDmsf.xapian_available`); without it, `search_files` is metadata-only.
  AI Helper adds no index of its own for DMSF, and no vector indexing of DMSF
  content is provided. A future index should handle revised, deleted and
  permission-changed documents without leaking old snippets.
- Office formats (`.docx`, `.xlsx`, `.pptx`, `.odt`) are not analyzed in this
  initial version. They require a vetted extraction/preview path.
- Historical revision comparison, folder navigation, DMSF approval workflows,
  and granular revision access beyond the project's current latest revision are
  intentionally out of scope.
- This module should be integration-tested against the installed DMSF version,
  particularly for per-document/approval access policies and the Active Storage
  API before being enabled for sensitive production document libraries.

The implementation has **no write tools** and leaves regular AI Helper behavior
unchanged when DMSF is absent.
