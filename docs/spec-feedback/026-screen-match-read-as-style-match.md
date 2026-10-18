# SF-026: Read "match the screen" as matching styles and wrote a style-level user story

**Date**: 2026-10-18
**Feature**: specs/079-fix-health-report-pdf-table (branch `bugfix/079-fix-health-report-pdf-table`)
**Artifact**: spec.md (User Story 5, FR-006, SC-006, SC-009, SC-010)
**Category**: intent-misread
**Related**: SF-024, SF-025

## Feedback

"User Story 5 is excessive. When I said to match the screen, I meant the PDF must not show something completely different, such as a bullet list where the screen shows a numbered list. It does not mean matching fine styles. Basically, the styles must not differ from what Redmine uses when it exports issues or wiki pages to PDF."

## What the AI Wrote

User Story 5 was titled "the PDF body reads with the same appearance as the screen". Its scenarios required, among other things:

> 「サマリー表」が太字で、本文より大きい文字で出る。
> 記号の種類は、画面と同じく入れ子の深さで変わる。
> それぞれが画面と同じ位置に、Redmine 本体の PDF と同じ見え方で出る(FR-006 の対応表)。

FR-006 had a table that gave a PDF style for each element. SC-006 checked list glyphs (● on the first level, ○ on the second). SC-009 required a "ruled" table.

## Correction

- User Story 5 now requires only that each element keep its kind, as on screen: headings stay headings, numbered lists stay numbered, bullet lists stay bullets, and tables stay tables. Styles are Redmine core's.
- FR-006 lost its per-element style table. It now lists the element kinds that must match the screen and forbids changing core's PDF styles.
- SC-006, SC-009 and SC-010 no longer check glyphs or borders.

## Root Cause

After SF-024, the AI took the user's words "everything the same as the screen" as a rule about rendering. It wrote that rule into the user story and the success criteria. SF-025 fixed the implementation approach (reuse Redmine core's renderer as is), but the AI only patched the wording of User Story 5. The story's title, its scenarios and its criteria still described styles. The AI did not ask what kind of difference the user cared about. That difference was a change of element kind, which is what the old PDF really did (numbers dropped, headings turned into plain text).

## Prevention

When a requirement says an export or alternate view must "match" a source, write it as a requirement on content and element kind: the same elements, the same kind for each, the same order and the same text. Leave styling to the target medium's existing standard, here Redmine core's exporter. When an implementation decision changes what "match" means (as in SF-025), rewrite every user story, FR and SC that used the old meaning, not just the sentence that triggered the change.

**Promoted to**: Not yet
