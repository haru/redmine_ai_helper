# SF-046: Proposed Open Color values for Redmine 6 without searching Redmine 6 for the counterpart

**Date**: 2026-11-21
**Feature**: specs/087-fix-popup-oc-colors (branch `bugfix/087-fix-popup-oc-colors`)
**Artifact**: spec.md
**Category**: convention-unknown
**Related**: SF-045, SF-018

## Feedback

"Since this is a plugin, it has to look the same as Redmine. On Redmine 7 it must match Redmine 7, and on Redmine 6 it must match Redmine 6's colors. If Redmine 6 has no Open Color, using Open Color on Redmine 6 is wrong."

## What the AI Wrote

The recommended option A, which the user first accepted, and FR-002 written from it:

> hover と active の背景は、Redmine 7 と同じ値 `#e9ecef` / `#dee2e6` でなければならない。

The option text claimed "hover / active は Redmine 6 に該当する色がない" and used the Open Color values as the fallback.

## Correction

- Added a Clarifications answer: Redmine 6 must never use Open Color values; every Redmine 6 value comes from Redmine 6's own CSS.
- Added a table mapping each value to its Redmine 7 source and Redmine 6 counterpart: the hover background is `#ddd` from `input[type="submit"]:hover, button[type="submit"]:hover` (the same selector Redmine 7 uses for `var(--oc-gray-2)`); the popup shadow on 6.1 comes from `div#sticky-issue-header`.
- FR-002 now requires `#ddd` for hover; the active background and the Redmine 6.0 shadow, which have no counterpart, became open questions. Added FR-006 forbidding Open Color values on Redmine 6.

## Root Cause

The AI looked for a Redmine 6 rule only on the selector the plugin's button resembles (`button`), found no hover there, and concluded Redmine 6 had no matching color. It did not first find which Redmine 7 rule each plugin value was copied from (`--oc-gray-2` is Redmine 7's submit-button hover) and then look up that same selector in Redmine 6, where `#ddd` exists. Lacking a counterpart, it filled the gap with the Redmine 7 value instead of asking, although AGENTS.md already requires asking when Redmine has no matching style (SF-018).

## Prevention

When a plugin style must match Redmine across supported versions, for each value first identify the Redmine rule (selector and line) it was taken from in the version it was written for, then read that same selector in every other supported version's stylesheet and use that version's value. If no version-specific counterpart exists, ask the user; never fill the gap with another version's value.

**Promoted to**: Not yet
