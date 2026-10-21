# SF-028: Kept sending an empty conversion result silently after choosing to report missing content

**Date**: 2026-10-21
**Feature**: specs/080-office-attachment-markdown (branch `080-office-attachment-markdown`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-027

## Feedback

During `/speckit-clarify`, the AI asked how an Office document whose conversion succeeds but yields no text (for example a slide deck that only contains pictures) should be passed to the LLM. The user chose "pass it with a notice that the document contains no text and that its content must not be guessed (English and Japanese); add the image notice too when image references exist", replacing the behaviour the AI had already written.

## What the AI Wrote

Edge Cases, "変換結果が空" (empty conversion result):

> 変換は成功したが Markdown が空(例: 画像だけの文書)の場合も、空の内容として LLM に渡す(変換失敗ではない)。

(If conversion succeeds but the Markdown is empty, e.g. an image-only document, pass the empty content to the LLM; it is not a conversion failure.)

## Correction

- The edge case now defines "no text" as nothing but whitespace left after removing image references, and refers to a new requirement.
- Added FR-015: such a document is sent with a "contains no text, do not guess" notice (English and Japanese), plus the FR-014 image notice when image references exist; it is not treated as a conversion failure.
- Added an acceptance scenario to User Story 1, extended the overlapping-notices edge case and FR-009.

## Root Cause

The AI wrote this edge case before the clarification session, when no policy for missing content existed, and treated "empty" as a valid result that needed no handling. Its example (an image-only document) was also wrong: Pandoc's GFM output keeps image references, so such a document is not empty. After the user chose notices for conversion failure, truncation and embedded images, the AI did not go back through the existing edge cases to find others that also lose content without telling the LLM; this one surfaced only as a later question. SF-027's second prevention rule (re-check edge cases of the same kind after a policy answer) applies, and this entry confirms it in the same session.

## Prevention

Before finishing a clarification session, list every edge case where content the user expects is not sent or is sent incomplete or empty, and check each one against the policy the answers set. Do not give an example of an edge case (such as "image-only document") without checking what the conversion actually outputs for it.

**Promoted to**: Not yet
