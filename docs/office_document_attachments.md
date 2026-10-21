# Office Document Attachments

The plugin sends Office documents attached to Issues, Wiki pages and Board messages to the LLM as Markdown text. The conversion is done by Redmine's Markdown preview for Office documents; the plugin does not run Pandoc itself (ADR-062).

## Prerequisites

- Redmine 7.0 or later. Redmine 6.x has no Markdown preview, so Office documents are ignored there, exactly as before.
- [Pandoc](https://pandoc.org/) available to Redmine. If it is not in the `PATH`, set `pandoc_command` in `config/configuration.yml`.
- Formats follow Redmine: `.docx` and `.odt` with any supported Pandoc, plus `.xlsx` and `.pptx` with Pandoc 3.8.3 or later. New formats added to Redmine are picked up without plugin changes.
- **Send attachments to LLM** is enabled on the AI Helper settings page.

If Redmine reports that a file cannot be previewed (for example, Pandoc is missing or too old for `.xlsx`), the plugin skips the file, as it skipped every Office file before this feature.

## Limits

- The plugin's maximum attachment size applies to the size of the original file. Larger files are neither converted nor sent.
- Redmine's own settings in `config/configuration.yml` apply to the conversion:

  | Setting | Default |
  |---|---|
  | `markdownized_preview_max_source_size` | 10 MB |
  | `markdownized_preview_max_output_size` | 100 KB |
  | `markdownized_preview_generation_timeout` | 10 seconds |

- The first conversion of a file runs synchronously in whatever needs it: a user request, or vector indexing of issues (`IssueContentAnalyzer`, including the `vector:regist` rake task). The result is cached in `derived_cache/markdownized_previews/`, the same cache that Redmine's preview screen uses, so a document that was already previewed is not converted again.

## What the LLM receives

The document is sent as an in-memory attachment named `<original file name>.md` with the MIME type `text/markdown`. The disk path of the file is never sent. The attachment kind reported in issue, wiki and board metadata is `document`.

Notices are appended to the Markdown (separated by a blank line) in this order. They are written in English or Japanese, following the user's locale.

| Notice | Sent when |
|---|---|
| Truncated | The converted text reached Redmine's output limit, so it was probably cut off. A document whose text is exactly the limit also gets this notice. |
| Images omitted | The Markdown contains an image reference (`![alt](path)` or an `<img>` tag). The images themselves are not sent. |
| No text | Nothing but whitespace remains after removing image references (including an empty conversion result). |
| Not converted | Redmine could not convert the file (Pandoc failed or timed out, or the source is over the size limit). Only this notice is sent, and the LLM is told not to guess the content. |

If the converted text reached Redmine's output limit and ends with a character that Redmine cut in the middle, only the incomplete bytes are removed. Any other invalid UTF-8, including an incomplete last character in text below the limit, raises an `EncodingError`. This is unexpected (Pandoc writes UTF-8) and typically means a damaged cache file. The error is not turned into a notice: it reaches the feature that sent the attachments, including vector indexing and similar-issue search, which no longer fall back to an empty analysis or a plain query for it.

## Logs

Messages go to the AI Helper log, which follows the `logger` section of `config/ai_helper/config.yml` (`log/ai_helper.log` unless `file` is set; Redmine's own log when the section is missing). The `info` message is written only when the log level is `info` or lower.

- `warn`: a conversion produced no result. The message includes the attachment id and file name. Redmine logs the cause (Pandoc exit status, timeout, source size, exception) in its own log, except when the file is no longer readable.
- `info`: a conversion result reached the output limit. The message includes the attachment id and file name.

## Known limitations

- When Pandoc writes an image with a caption as `<figure>…<figcaption>…</figcaption></figure>`, the caption is sent as text and the "No text" notice is not added; the "Images omitted" notice is still added.
- Pandoc's actual image output for `.docx`, `.pptx` and `.xlsx` files has not been verified automatically (CI has no Pandoc); see the manual check in `specs/080-office-attachment-markdown/quickstart.md`.
