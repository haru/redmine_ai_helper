# SF-047: Required display conditions to follow the switched-to project without reading the partial that decides them

**Date**: 2026-11-21
**Feature**: specs/088-fix-issue-form-rerender (branch `bugfix/088-fix-issue-form-rerender`)
**Artifact**: spec.md (also quickstart.md, tasks.md, plan.md)
**Category**: convention-unknown
**Related**: SF-008, SF-013, SF-043

## Feedback

After the browser check showed that the edit form keeps the AI Helper features when the project is changed to one where the module is disabled, the user said: "Do not fix the code; fix the specification."

## What the AI Wrote

FR-005, US3 and SC-003 required the display conditions to follow the project the user switches to, in every issue form:

> 各機能の表示条件(プロジェクトで AI Helper モジュールが有効か、…)は、再描画後のフォームの内容(切り替え後のプロジェクトなど)に従って判定されなければならない。
> **SC-003**: AI Helper が無効なプロジェクトに切り替えたとき、AI Helper のフォーム内機能が 1 つも表示されない

The edge case and quickstart step 13 said that after switching an edit form to a disabled project, the description features and the assignee suggestion disappear.

## Correction

- Added a Clarifications session "browser check" and rewrote FR-005, SC-003, US3 (goal, independent test, scenarios 1, 3, 4), the edit-form edge case, an Assumptions bullet, quickstart steps 8, 9 and 13, the tasks.md Phase 5 goal and T029 note, and one plan.md row.
- The display condition stays as the server decides it today (`project = @project || @issue.project` in `_textarea_overlay.html.erb`). Only the global "New issue" page (`/issues/new`, no `@project`) judges by the switched-to project; the project-scoped new form and the edit form keep the page-load project. The assignee suggestion endpoint is built from the same `project`, so in the project-scoped new form it stays on the page project while the completion endpoint (`@issue.project`) follows the switch.

## Root Cause

The AI treated "judged by the re-rendered form's project" as how the server already works, because the JS design (a settings container present or absent after re-render) made it look so, and it wrote the requirement and the quickstart expectation without reading line 5 of the partial. The partial prefers `@project`, which Redmine does not update when the edit form or a project-scoped new form is re-rendered. Only a real browser check (changing the project in each form) exposed it. AGENTS.md already requires reading the existing code before a spec states how it behaves (SF-008), but the AI applied it to the JS side only, not to the server-side condition that feeds the JS.

## Prevention

When a spec requires a display condition to follow a value that changes on re-render (the selected project, tracker, status), find the code that decides the condition on the server, quote the expression it uses, and check, for each form type that re-renders (global new, project-scoped new, edit), whether that value is the one the expression reads. Write the requirement per form type, and measure the project-switch case in each form before the spec says it works.

**Promoted to**: Not yet
