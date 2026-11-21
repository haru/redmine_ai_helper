# SF-045: Offered popup colors per Redmine version instead of the sidebar the popup comes from

**Date**: 2026-11-21
**Feature**: specs/087-fix-popup-oc-colors (branch `bugfix/087-fix-popup-oc-colors`)
**Artifact**: spec.md
**Category**: convention-unknown
**Related**: SF-032

## Feedback

"The popup having a different color from the sidebar is wrong in the first place. The popup is detached from the sidebar, so on both Redmine 7 and Redmine 6 it should have the same colors as the sidebar."

## What the AI Wrote

FR-001 left the Redmine 6 colors open ("各色は [NEEDS CLARIFICATION: Redmine 6 で使う色をどうするか(下記 Q1)]"). Q1 offered two options:

- A: use the Open Color values (`#f8f9fa`, `#ced4da`, ...) on Redmine 6 too, so that Redmine 6 and 7 look the same.
- B: use Redmine 6 core colors, taking the background from `#sidebar` but presenting it as "matching Redmine 6", with the Open Color values for anything Redmine 6 has no color for.

Neither option stated the rule "the popup has the colors of the sidebar of the running Redmine". Option A would have made the Redmine 6 popup differ from the Redmine 6 sidebar.

## Correction

FR-001 now requires the popup background, border and divider to equal the running Redmine's `#sidebar` background, `#sidebar` start-side border and `#sidebar hr` background, on both Redmine 6 and 7. Clarifications gained a table mapping each popup color to its sidebar declaration for Redmine 6.0/6.1 (`#f9fafb`, `#d0d7de`, `#ccc`) and Redmine 7.0/master (`var(--oc-gray-0)`, `var(--oc-gray-4)`, `var(--oc-gray-4)`). The Redmine 7 popup already uses those variables, so it is unchanged. The shadow has no sidebar counterpart and is kept outside this rule.

## Root Cause

The AI framed the question around the defect's cause (variables missing in Redmine 6) and so compared "Redmine 6 colors" with "Redmine 7 colors". It did not go back to what the popup is: the 083 spec describes it as the sidebar chat form moved out of the sidebar, and the popup CSS itself says its values are "Copied from Redmine's #sidebar". Those two sources make the sidebar the reference for every color, independent of version; the AI read the CSS comment but treated it as provenance, not as the rule the colors must keep.

## Prevention

When a spec chooses visual properties for a UI element that was moved out of, or copied from, another element (popup from sidebar, export from screen), first look up what the original element uses on every supported Redmine version and offer "same as the original element on each version" as an option; do not frame the choice around one version's values.

**Promoted to**: Not yet
