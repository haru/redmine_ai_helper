# CRF-088: Collection setters wrote to the database before save, so a failed save left the change behind

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-errors, speckit-review-code)
**Feature**: branch `feature/084-project-management-tools`
**Files**: lib/redmine_ai_helper/tools/project_write_tools.rb, lib/redmine_ai_helper/tools/member_tools.rb
**Category**: error-handling
**Related**: None

## Feedback

The reviewers found that `update_modules`, `add_trackers`, `remove_trackers`, and `update_member_roles` returned `{ error: "Failed to ..." }` after the change was already stored, and that `remove_member` ignored the result of `member.destroy`.

## Original Code

```ruby
project.tracker_ids = new_ids
raise UserError, "Failed to add trackers: ..." unless project.save
```

## Fix

Assignment and `save` now share an `ActiveRecord::Base.transaction` (`assign_trackers!`, the module and member-role blocks), and `remove_member` calls `destroy!` in a transaction. Tests stub `save` to return false (or `destroy` to return false) and assert the rows are unchanged.

## Root Cause

The AI followed the "validate everything, then save once" idea from research R-016 and treated `x = ...; x.save` as one write. It did not read what `enabled_module_names=`, `tracker_ids=`, and `Member#role_ids=` do on a saved record (they write immediately), and the tests only used inputs for which `save` succeeds, so the gap was invisible.

## Prevention

Before writing `record.assoc_ids = ...; record.save` on a persisted record, read the Rails/Redmine setter: if it writes immediately (has_many / habtm / `role_ids=`), wrap the assignment and the save in one transaction and add a test that stubs `save` (or `destroy`) to fail and asserts the rows are unchanged. Use `destroy!`, never an ignored `destroy`, in a write tool.

**Promoted to**: Not yet
