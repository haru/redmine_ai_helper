# CRF-090: update_category revealed the project id of a category the caller could not see

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-errors, speckit-review-code)
**Feature**: branch `feature/084-project-management-tools`
**Files**: lib/redmine_ai_helper/tools/category_tools.rb
**Category**: permission
**Related**: None

## Feedback

A category in an invisible project returned `Project not found. id = N`, while a missing category returned `Category not found`, which confirmed the category existed and exposed its project id.

## Original Code

```ruby
category = IssueCategory.find_by(id: category_id)
raise UserError, "Category not found..." if category.nil?
project = writable_project!(project_id: category.project_id, ...)
```

## Fix

A category whose project is not visible is reported as `Category not found. id = N`, the same as a missing one. A test creates a private project with a category and checks the message and that nothing changed.

## Root Cause

The AI reused the guard that fetches a project by id without thinking that the id came from a lookup that already proved the object exists. The ADR's "check permissions on every object" rule was applied to the project but not to what the error message reveals.

## Prevention

When a tool looks an object up by its own id and then checks its parent's visibility, report an invisible parent exactly like a missing object (same message). Add a test that compares both cases.

**Promoted to**: Not yet
