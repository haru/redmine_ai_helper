---
title: Office Attachments Sent as Markdown Preview
type: decision
sources: [S056]
updated: 2026-10-21
---

# Office Attachments Sent as Markdown Preview

ADR-062 / Issue #532: Word, Excel, PowerPoint and LibreOffice files were silently dropped
from LLM attachments, and an Office-only container made `analyze_content_files` fail with
"No supported file attachments found." (S056). User-facing summary:
[Multi-modal File Support](./multi-modal-file-support.md).

## Decision

- **Selection**: a file outside the plugin's extension list is sent when
  `respond_to?(:markdownized_previewable?) && markdownized_previewable?`. The plugin checks no
  extensions, Pandoc or Redmine version itself; Redmine 6.x lacks the methods, so its behavior is
  unchanged. Extension-list files are evaluated first (S056).
- **Content**: `Attachment#markdownized_preview_content`, so the preview cache is shared with
  Redmine's screen (S056). Sent as `RubyLLM::Attachment(StringIO, filename: "<name>.md")`.
- **Why `.md`**: RubyLLM derives the MIME type from the filename via Marcel. The original name
  gives a `:document`, which the Anthropic and Gemini protocols reject with
  `UnsupportedAttachmentError`; `x.docx.md` gives `text/markdown`, inlined as text (S056).
- **Metadata**: `attachment_file_type` returns `"document"`; the Office branch in
  `llm_attachment_source` runs before `text_attachment?`, or the binary would be read as text (S056).

## Result handling

| Result | Behavior (S056) |
|---|---|
| `nil` | warn log (attachment id, filename) + attachment holding only a "could not be converted" notice |
| other non-String | `TypeError` |
| size >= `Redmine::Markdownizer::MAX_OUTPUT_SIZE` | treated as truncated: notice + info log |
| invalid UTF-8 | see below |
| image reference (`![..](..)` or `<img>`) | "images omitted" notice |
| nothing but image references | "no text" notice |

Notices are appended in the fixed order truncated → images → no text; texts are prompt templates
in `assets/prompt_templates/attachment_file_helper/` (en/ja) (S056).

**UTF-8**: Redmine cuts output by bytes, so a multi-byte character can be split. Only for a
result treated as truncated, an incomplete trailing character (at most 3 bytes) is dropped.
Any other invalid byte raises `EncodingError`; `scrub` is avoided because it would inject U+FFFD (S056).

## Consequences and gotchas

- All six attachment-sending features work through the shared helper without code changes (S056).
- The first conversion runs synchronously in the caller (Redmine timeout, default 10 s) (S056).
- Vector indexing: `IssueContentAnalyzer#analyze` now rescues only `RubyLLM::Error` and
  `Faraday::Error` around the LLM call, and `VectorTools#build_hybrid_query` no longer rescues, so
  an attachment `EncodingError`/`TypeError` stops indexing of that issue and similar-issue search
  instead of becoming an empty analysis or plain query (S056). See [Vector Search](./vector-search.md).
- A result exactly at the limit also gets the truncation notice, because Redmine does not report
  whether it cut (S056).
- Not verified against real Pandoc output (none in the dev environment): image-reference form
  is confirmed manually. A figure left as `<figure>/<figcaption>` gets the images notice but not
  the no-text notice (S056).

## Rejected alternatives

Adding `docx`/`xlsx` to the extension list (ignores Pandoc availability/version); calling
`Redmine::Markdownizer.convert` or Pandoc directly (duplicates cache path and error handling);
sending the original file as `:document` (APIs reject it); `Redmine::VERSION::MAJOR >= 7` or
`defined?(Redmine::Markdownizer)` (feature detection per object keeps 6.x tests mock-friendly);
keeping the original filename; replacing the extension with `.md` (collides with a real `spec.md`) (S056).
