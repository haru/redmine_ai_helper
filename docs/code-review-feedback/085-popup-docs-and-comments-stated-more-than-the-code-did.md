# CRF-085: Popup ADR, research and comments described tooltips as modals and overstated what was saved

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: docs/adr/064-chat-popup-moves-the-sidebar-element.md, specs/083-chat-form-popup/research.md, assets/javascripts/chat/ai_helper_chat_popup.js, assets/javascripts/chat/ai_helper_chat.js, assets/stylesheets/ai_helper.css
**Category**: doc-comment
**Related**: CRF-076

## Feedback

- The 10001 z-index belongs to tooltips; the plugin's modals are 9998-9999.
- 'Saved on `pointerup` only' and 'the fitted value is not saved' did not match the code; the scroll comment did not match the order of the calls; the z-index thresholds (above 1000 / below 100) did not match R-006 (100 / 1000); the JSDoc of `initChatForm`, `initSidebar` and `init` omitted what they now do; line references were stale.

## Original Code

```
The plugin's own modals use 10001 and stay above both.
```

## Fix

ADR, research, the CSS comment and the JSDoc were corrected to the code, selector names replace line numbers where they rot, and the behaviour that was wrong was fixed in code (see CRF-081).

## Root Cause

The wording was taken from the research decision without grepping the stylesheet for the 10001 rule, and comments were written before the final order of calls.

## Prevention

- Before writing a number or a name into a comment or ADR, grep the code for it; when an ADR or comment summarises research, take the thresholds and scope from the cited R-NNN section.

**Promoted to**: Not yet
