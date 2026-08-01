---
title: Multi-modal File Support
type: reference
sources: [S002]
updated: 2026-08-01
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

(Image detection is extension-based, matching Redmine's `Attachment#image?`.)

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
