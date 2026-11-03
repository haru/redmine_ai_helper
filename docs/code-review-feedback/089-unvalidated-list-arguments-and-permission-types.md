# CRF-089: List arguments and the permission argument were coerced or accepted without checking their types

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-types, speckit-review-errors)
**Feature**: branch `feature/084-project-management-tools`
**Files**: lib/redmine_ai_helper/tools/project_write_tools.rb, lib/redmine_ai_helper/tools/member_tools.rb, lib/redmine_ai_helper/util/project_write_guard.rb, lib/redmine_ai_helper/tools/project_tools.rb
**Category**: error-handling
**Related**: CRF-009

## Feedback

`Array(x)` turned scalars into one-element lists and let a scalar `role_ids` reach `Member#role_ids=` (NoMethodError); string ids produced misleading "not found" errors; `custom_fields` of the wrong shape raised NoMethodError/TypeError; `writable_project!(permission: nil)` skipped the permission check; `permission_name` and `possible_values_options` handling absorbed unexpected types with `to_s` / `Array()`.

## Original Code

```ruby
role_ids = Array(role_ids)
...
member.role_ids = role_ids   # the raw argument
```

## Fix

Each boundary now checks `is_a?(Array)` and the element type and returns a precise `UserError` (`validate_role_ids!`, `validate_id_list!`, `validate_tracker_ids!`, `validate_string_list!`, `normalize_custom_fields`). The guard raises `ArgumentError` for a nil or non-Symbol/Hash permission, `permission_name` and `possible_value_hash` branch with `case` and raise on `else`. The validated value is returned and used.

## Root Cause

The AI used `Array()` as a convenient idiom and assumed the JSON schema guarantees the types, although MCP clients and LLMs can send any shape. AGENTS.md (CRF-003/009, CRF-050) already requires explicit branching and boundary validation; it was not consulted for tool arguments.

## Prevention

For every tool argument documented as a list, check `is_a?(Array)` and the element class at the start of the tool, return the validated value, and use that value afterwards. Never use `Array()`, `to_s`, or `&.` to absorb a union; add a test with a scalar, a wrong element type, and nil.

**Promoted to**: Not yet
