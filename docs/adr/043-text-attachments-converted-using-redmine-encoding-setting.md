# ADR-043: Text Attachments Are Converted to UTF-8 Using Redmine's Encoding Setting

**Date**: 2026-10-01
**Status**: Accepted

## Context

When a text attachment saved in a non-UTF-8 encoding (for example Shift-JIS)
is attached to an issue or wiki page, every AI feature that sends attachments
to the LLM fails with `"\x83" from ASCII-8BIT to UTF-8` (Issue #471). RubyLLM
1.16 reads attachments as binary and embeds text files verbatim into the
request body, so `JSON.generate` raises on bytes that are not valid UTF-8.
RubyLLM 2.0 avoids the exception by scrubbing invalid bytes to U+FFFD, which
silently destroys the content instead.

Redmine core already displays such attachments correctly by trying the
encodings listed in the global setting "Attachments and repositories
encodings" (`Setting.repositories_encodings`) in order.

## Decision

`RedmineAiHelper::Util::AttachmentFileHelper#supported_attachment_paths`
normalizes text attachments (document and code types other than PDF) before
they are handed to RubyLLM:

1. Content that is already valid UTF-8 is passed unchanged as a disk path,
   regardless of the setting's order. This intentionally differs from Redmine
   core, which may misread UTF-8 files when another encoding is listed first.
2. Otherwise, the encodings in `Setting.repositories_encodings` are tried in
   order, exactly as written (no aliasing such as `shift_jis` → `cp932`, no
   extra candidates). The first encoding that converts to valid UTF-8 without
   raising wins, and the result is passed as an in-memory
   `RubyLLM::Attachment` carrying the original filename.
3. If no encoding works (including an empty setting), the content is not sent.
   A warning with the attachment ID and filename is logged, and a placeholder
   attachment with the same filename whose content is a short note ("this file
   could not be read because of its character encoding") is sent instead, so
   the LLM knows the file is missing.

Statistical encoding detection (NKF, rchardet, charlock_holmes) is not used.

## Consequences

- Attachments that Redmine core can display are readable by AI Helper, and
  one unreadable attachment no longer breaks the whole feature.
- Administrators control behavior through an existing core setting; files with
  Windows-specific characters require `cp932` rather than `shift_jis` in that
  setting, matching core's display behavior.
- Callers are unchanged: the method still returns sources accepted by
  RubyLLM's `with:`, now a mix of path strings and `RubyLLM::Attachment`
  objects.
- Excluded content is traceable through logs and the in-request note; it is not
  a silent fallback.
- Short half-width-katakana-only EUC-JP files may still be misread as
  Shift-JIS when `shift_jis` precedes `euc-jp`, the same as in Redmine core.
