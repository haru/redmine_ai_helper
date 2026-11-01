# CRF-086: Popup icon-only links lost their accessible name when the tooltip was removed

**Date**: 2026-11-01
**Source**: GitHub Copilot (PR #544)
**Feature**: branch `feature/083-chat-form-popup` / PR #544
**Files**: app/views/ai_helper/chat/_sidebar.html.erb, config/locales/en.yml, config/locales/ja.yml, test/functional/ai_helper_view_hook_test.rb
**Category**: convention-violation
**Related**: None

## Feedback

The popup open/close links contain only an SVG icon and no text. With `title` removed, screen readers expose anonymous links. Add localized `aria-label` values while keeping the links tooltip-free (https://github.com/haru/redmine_ai_helper/pull/544#discussion_r4434365086).

## Original Code

```erb
<%= link_to sprite_icon("close"), "#", id: "aihelper-popup-close", class: "aihelper-popup-button icon-only" %>
```

## Fix

Added `aria-label` from new locale keys `label_ai_helper_popup_open` / `label_ai_helper_popup_close` (en, ja). The functional test now asserts the labels while still asserting there is no `title`.

## Root Cause

The user asked to remove the tooltips (`title`), and `title` was the only accessible name the links had. The removal was applied literally without checking that it was also the links' only text alternative.

## Prevention

- When removing or replacing an attribute that supplies a visible or accessible label (`title`, text), check what accessible name remains for the element; an icon-only link or button always needs an `aria-label` (localized via `t()`), and the test asserts it.

**Promoted to**: Not yet
