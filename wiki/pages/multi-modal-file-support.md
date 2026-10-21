---
title: Multi-modal File Support
type: reference
sources: [S002, S056]
updated: 2026-10-21
---

# Multi-modal File Support

The plugin can send files attached to Issues, Wiki pages, and Board messages to
the LLM alongside the text, so the AI can reference attachment contents in
summaries and chat (S002).

## Supported file types

| Category | Extensions |
|---|---|
| Images | .jpg, .jpeg, .png, .gif, .webp, .bmp |
| Documents | .pdf, .txt, .md, .csv, .json, .xml |
| Code | .rb, .py, .js, .html, .css, and more |
| Audio | .mp3, .wav, .m4a, .ogg, .flac |
| Office documents | .docx, .odt (and .xlsx, .pptx with Pandoc 3.8.3+) — see below |

(Image detection is extension-based, matching Redmine's `Attachment#image?`.)

## Office documents

Office documents are sent as the Markdown produced by Redmine's Markdown preview
(`Attachment#markdownized_preview_content`), as an in-memory attachment named
`<original name>.md` (`text/markdown`) (S056). The plugin does not run Pandoc itself.

- Requires Redmine 7.0+ and Pandoc (`pandoc_command`); `.xlsx` / `.pptx` need Pandoc 3.8.3+.
  On Redmine 6.x or without Pandoc, Office documents are skipped as before (S056).
- Redmine's `markdownized_preview_max_source_size` (10 MB), `markdownized_preview_max_output_size`
  (100 KB) and `markdownized_preview_generation_timeout` (10 s) apply; the conversion cache is shared
  with Redmine's preview screen (S056).
- The plugin's max attachment size applies to the original file (S056).
- Notices appended for the LLM: conversion failure (only the notice is sent, warn log),
  truncation at the output limit (info log), images omitted, and no text (S056).
- The disk path is never sent. Details: [docs/office_document_attachments.md](../../docs/office_document_attachments.md),
  [ADR-062](../../docs/adr/062-office-attachments-sent-as-redmine-markdown-preview.md).

## Enabling and the size limit

On the AI Helper admin settings page, check **"Send attachments to LLM"** and
optionally set a max file size (**default 3 MB**). Files exceeding the limit are
**not** sent to the LLM (S002). You can also ask the AI to analyze specific
attachments directly using the file-analysis tools (S002).

## Interaction with vector search

When [vector search](./vector-search.md) is enabled, attachment contents are
also incorporated into the vector index — the LLM analyzes attachments during
index registration and similar-issue search, improving similarity matching for
issues with meaningful attachments (S002).

## Related

- [Plugin Overview](./plugin-overview.md)
