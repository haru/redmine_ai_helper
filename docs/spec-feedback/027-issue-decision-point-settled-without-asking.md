# SF-027: Settled an issue's open decision point on embedded images without asking

**Date**: 2026-10-21
**Feature**: specs/080-office-attachment-markdown (branch `080-office-attachment-markdown`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-019, SF-020

## Feedback

During `/speckit-clarify`, the AI asked whether the LLM should be told that images and charts inside Office documents are not sent. The user chose "add a notice at the end of the content, only for documents that contain images (English and Japanese)", replacing the behaviour the AI had already written.

## What the AI Wrote

Edge Cases, "文書内の画像・グラフ" (images and charts inside documents):

> Markdown にはテキストと表だけが残り、画像は送られない。これは制限として受け入れ、ドキュメントに記載する。

(Only text and tables remain in the Markdown, and images are not sent. This is accepted as a limitation and documented.)

## Correction

- The edge case now says image references remain in the converted Markdown and that documents containing them get a notice.
- Added FR-014: when the converted Markdown contains an image reference (Markdown image syntax or an HTML image tag), append a notice telling the LLM that the document's images are not included and must not be guessed; documents without image references get no notice. The notice text exists in English and Japanese.
- Added an acceptance scenario to User Story 1, an edge case for documents that need both the truncation and the image notice, and updated FR-009, FR-013 and the Assumptions.

## Root Cause

Issue #532 listed "Embedded images are lost" under "Points to Decide". The AI asked about two of the listed points (conversion failure and truncation) but settled this one itself as a documented limitation, because it treated the image loss as an inherent constraint of the conversion rather than as a choice about what the LLM is told. It did not check what Pandoc's GFM output leaves in place of an image (a reference to a file that is not sent), which would have shown that the LLM sees the image exists and may guess its content — the same risk the user had just chosen to guard against with notices for failure and truncation. It should have asked about every point the issue marked as open, and noticed that the earlier answers set a pattern this point also fitted.

## Prevention

When the source request (issue, design note) lists points to decide, the spec either asks the user about each point or quotes the request's own answer for it; the AI does not settle a listed point itself. After a clarification answer sets a policy (e.g. "tell the LLM when content is missing"), re-check the other edge cases of the same kind against that policy and ask about any that differ.

**Promoted to**: Not yet
