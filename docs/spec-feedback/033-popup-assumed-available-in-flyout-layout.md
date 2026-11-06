# SF-033: Assumed the popup stays available in the narrow flyout layout without asking

**Date**: 2026-11-01
**Feature**: specs/083-chat-form-popup (branch `feature/083-chat-form-popup`)
**Artifact**: spec.md
**Category**: unconfirmed-assumption
**Related**: SF-032

## Feedback

Answering a clarification question, the user chose to make the popup unavailable in the narrow layout where Redmine moves the sidebar into the flyout menu.

## What the AI Wrote

An edge case in spec.md: "In the narrow layout where the sidebar is stored in the flyout menu, the icon is shown in the menu with the other sidebar elements and the popup is shown inside the viewport."

## Correction

FR-001 now forbids the icon and the popup in that layout. The edge case now says that the popup is hidden and the chat shown in the menu when the screen narrows during popup display, and that the popup returns when the width is restored unless it was closed.

## Root Cause

The AI had read Redmine's `responsive.css` and `responsive.js`, so it knew the sidebar moves into the flyout, but it extended the desktop behaviour to that layout without checking that dragging, resizing and the popup's purpose still apply there. The feature's purpose, a form too narrow in the sidebar, does not arise in a full-width menu.

## Prevention

When a spec adds a UI feature tied to a page region, check how Redmine's responsive layout relocates that region, and ask the user whether the feature applies to the narrow layout before writing an edge case for it.

**Promoted to**: Not yet
