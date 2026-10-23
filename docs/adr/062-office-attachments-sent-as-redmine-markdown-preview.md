# ADR-062: Send Office attachments to the LLM as Redmine's Markdown preview

**Date**: 2026-10-21
**Status**: Accepted

## Context

Attachments are sent to the LLM through `AttachmentFileHelper#supported_attachment_paths`,
which selects files by a fixed extension list (images, audio, PDF, text, code).
Word, Excel, PowerPoint and LibreOffice Writer files were dropped without notice,
and an Office-only container made `analyze_content_files` fail with "No supported
file attachments found." LLM APIs do not accept these formats: RubyLLM classifies
them as `:document`, which the Anthropic and Gemini protocols reject with
`UnsupportedAttachmentError` (Issue #532).

Redmine 7.0 added a Markdown preview for Office documents. `Attachment#markdownized_preview_content`
converts the file with Pandoc (`pandoc <file> -t gfm`), caches the result under
`derived_cache/markdownized_previews/`, returns `nil` on any failure (non-zero exit,
timeout, source over `markdownized_preview_max_source_size`, other exceptions),
and silently cuts the result at `markdownized_preview_max_output_size` bytes.
Redmine 6.x has none of these methods, and the plugin supports Redmine 6.0+.

## Decision

- An attachment outside the existing extension list is sent when
  `attachment.respond_to?(:markdownized_previewable?) && attachment.markdownized_previewable?`.
  The plugin does not check extensions, Pandoc or the Redmine version itself.
  The existing enable flag, size limit (on the source file) and existence check apply.
- The content is `markdownized_preview_content`, so the preview cache is shared
  with the Redmine screen. It is sent as `RubyLLM::Attachment(StringIO, filename: "<name>.md")`,
  which RubyLLM detects as `text/markdown` and inlines as text.
- When the result reaches the output limit, the bytes are made valid UTF-8 by
  dropping an incomplete trailing character (at most 3 bytes) left by Redmine's
  byte cut. Any other invalid byte, including an incomplete last character below
  the limit, raises `EncodingError`. A result that is neither a String nor `nil`
  raises `TypeError`.
- `IssueContentAnalyzer#analyze` rescues only `RubyLLM::Error` and `Faraday::Error`
  around the LLM call, and `VectorTools#build_hybrid_query` no longer rescues, so
  these errors reach vector indexing and similar-issue search instead of becoming
  an empty analysis or a plain query.
- When the result is `nil`, the plugin logs a warning with the attachment id and
  filename and sends an attachment holding only a "could not be converted" notice.
- Notices are appended to the content when the result reaches
  `Redmine::Markdownizer::MAX_OUTPUT_SIZE` (treated as truncated), contains image
  references (Markdown image syntax or `<img>`), or has no text once image
  references are removed. Notice texts are prompt templates in English and Japanese.
- `attachment_file_type` returns `"document"` for these attachments.

## Consequences

- All six features that send attachments (issue summary, reply draft, sub-issue
  draft, wiki summary, `analyze_content_files` including MCP, vector indexing)
  handle Office documents without changes to their code.
- Supported formats follow Redmine: `.docx`/`.odt` with Pandoc, plus `.xlsx`/`.pptx`
  with Pandoc 3.8.3+. New formats added to Redmine are picked up without plugin changes.
- On Redmine 6.x or without Pandoc, the set of attachments sent is unchanged.
- The first conversion runs synchronously in the caller, a user request or vector
  indexing (up to Redmine's timeout, default 10 s); later calls read the cache.
- An attachment error (`EncodingError`) now stops vector indexing of that issue and
  similar-issue search, which previously turned every error into an empty analysis
  or a plain query.
- Images inside documents are not sent; the LLM is told so instead.
- A document whose output is exactly the size limit also gets the truncation notice,
  because Redmine does not report whether it cut the output.

## Alternatives considered

- Adding `docx`/`xlsx`/… to the plugin's extension list: breaks FR-001 (follow
  Redmine's own judgement instead of checking extensions) and cannot reflect
  whether Pandoc is available or its version (research R-003).
- Calling `Redmine::Markdownizer.convert` directly: duplicates Redmine's cache path
  and error handling (research R-001).
- Calling Pandoc from the plugin: forbidden by FR-012 (research R-001).
- Sending the original file as a RubyLLM `:document` attachment: the LLM APIs do not
  accept it (research R-001, R-004).
- Checking `Redmine::VERSION::MAJOR >= 7`: forbidden by FR-003, which requires
  checking whether the feature exists (research R-002).
- Checking `defined?(Redmine::Markdownizer)`: detects the feature, but testing the
  Redmine 6.x branch with mock attachments would need global constant changes
  (research R-002).
- Keeping the original filename: RubyLLM classifies it as `:document` and the request
  cannot be sent (research R-004).
