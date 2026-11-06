# SF-035: Chose a generic icon for "open in popup" without asking

**Date**: 2026-11-01
**Feature**: specs/083-chat-form-popup (branch `feature/083-chat-form-popup`)
**Artifact**: contracts/ui-contract.md
**Category**: unconfirmed-assumption
**Related**: SF-019, SF-020

## Feedback

The user said the popup icon was not good and asked for a better one. After the AI proposed options, the user supplied their own icon (Tabler `queue-pop-out`: a window with an arrow leaving the top-right corner) and asked to use it.

## What the AI Wrote

The UI contract specified the open button as `sprite_icon("maximize")`, an existing Redmine icon.

## Correction

The contract now specifies a plugin-provided icon, `sprite_icon("ai-helper-popup-open", plugin: :redmine_ai_helper)`, added to `assets/images/icons.svg` from the user's SVG.

## Root Cause

The icon is a user-visible presentation choice. The AI picked the nearest icon in Redmine's sprite (`maximize`) for implementation ease and did not present alternatives. `maximize` reads as "full screen", not "move into a popup window", so the meaning did not match the action. The AI should have listed the candidate icons (Redmine's stock set vs. a new one) and asked, as AGENTS.md requires for choices the user can see.

## Prevention

When a spec names an icon for a new control, check that its common meaning matches the action, and ask the user with options when no stock Redmine icon (`app/assets/images/icons.svg`) clearly expresses it. Do not settle the icon on implementation-cost grounds.

**Promoted to**: Not yet
