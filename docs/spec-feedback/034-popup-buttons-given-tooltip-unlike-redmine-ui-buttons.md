# SF-034: Gave the popup buttons a tooltip although Redmine's UI-operation buttons have none

**Date**: 2026-11-01
**Feature**: specs/083-chat-form-popup (branch `feature/083-chat-form-popup`)
**Artifact**: contracts/ui-contract.md
**Category**: convention-unknown
**Related**: SF-017, SF-018

## Feedback

After the popup open/close buttons were shown, the user asked why only this feature shows a tooltip ("Open in popup" / "Close popup") and said it is unnatural and inconsistent. The AI answered that Redmine core puts `title` on icon-only buttons (timelog "options", download links). The user rejected that: those are add/feature buttons, and UI-operation buttons such as closing the sidebar have no title. "Do not make only this plugin a special UI. What matters is consistency across Redmine." The user chose to remove the titles.

## What the AI Wrote

The UI contract table specified the two buttons as:

- `#aihelper-popup-open`: `sprite_icon("maximize")`, `title` is `label_ai_helper_popup_open`
- `#aihelper-popup-close`: `sprite_icon("close")`, `title` is `label_ai_helper_popup_close`

and a "Locale" section adding the two `label_ai_helper_popup_*` keys to `en.yml` and `ja.yml`.

## Correction

Both buttons now have no `title`, like Redmine's `#sidebar-switch-button` (`app/views/layouts/base.html.erb`, a bare `<a>` with an icon). The contract rows say "no `title`", the Locale section says no dedicated locale keys are added, and the two keys were removed from `en.yml` and `ja.yml`.

## Root Cause

The AI treated "icon-only button" as one category and gave it a `title` for accessibility and discoverability. It never looked at the Redmine control that does the same job (the sidebar collapse switch), which has no title. When challenged, it again generalised from other icon-only buttons (add/feature buttons) instead of the matching kind (UI-operation buttons). It should have found the closest existing Redmine control for each new element and copied its markup attributes, not only its look.

## Prevention

When a spec defines a new control, name the closest existing Redmine control with the same role (for example layout toggle vs. add/edit action), read its markup in `app/views` / `layouts/base.html.erb`, and copy its attributes (`title`, label text, classes). If the new control would carry an attribute the Redmine counterpart lacks (a tooltip, a label, a confirmation), ask the user instead of specifying it.

**Promoted to**: Not yet
