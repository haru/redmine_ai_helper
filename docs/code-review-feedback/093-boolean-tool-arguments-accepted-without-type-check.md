# CRF-093: Boolean tool arguments were accepted or ignored without checking their type

**Date**: 2026-11-03
**Source**: GitHub Copilot (PR #549)
**Feature**: branch `feature/084-project-management-tools` / PR #549
**Files**: lib/redmine_ai_helper/base_tools.rb, lib/redmine_ai_helper/tools/project_write_tools.rb, lib/redmine_ai_helper/tools/category_tools.rb, test/unit/tools/project_write_tools_test.rb, test/unit/tools/category_tools_test.rb
**Category**: error-handling
**Related**: CRF-089, CRF-009

## Feedback

`is_public` is declared as a boolean, but `create_project` / `update_project`
passed any non-nil value to `safe_attributes=`. Rails casts a string such as
`"no"` to `true`, so a malformed call could make a project public instead of
being rejected
(<https://github.com/haru/redmine_ai_helper/pull/549#discussion_r4449777220>).

The reviewer said MCP calls skip schema validation. That part is wrong: the
mcp gem 1.8.2 validates tool call arguments by default
(`validate_tool_call_arguments: true`), and the plugin does not turn it off.
Chat tool calls through RubyLLM are not validated, though, so the defect
applies there.

A grep for the other boolean properties found the same defect beyond the
flagged line:

- `inherit_members` (`create_project`, `update_project`): cast the same way as
  `is_public`.
- `clear_parent` (`update_project`) and `clear_assigned_to`
  (`update_category`): compared with `== true`, so `"true"` was silently
  ignored and the call returned success without the change.

## Original Code

```ruby
attrs = { "is_public" => is_public, "inherit_members" => inherit_members }.compact
...
category.assigned_to_id = nil if clear_assigned_to == true
```

## Fix

Added `BaseTools#validate_booleans!`, which raises
`UserError "<name> must be true or false"` for anything other than `true`,
`false`, or `nil`. `create_project`, `update_project`, and `update_category`
call it before the attribute permission checks. New tests pass values that
would otherwise flip the attribute (`"no"`, `"true"`, `1`) or be ignored. They
failed before the fix and assert that the record did not change. The decision
is recorded in ADR-069, decision 3.

## Root Cause

CRF-089 added type checks for the list arguments of the same tools, but it
treated the problem as one of lists (`Array()` coercion). The AI did not
apply the same reasoning to scalar arguments. It relied on the JSON schema
`type: "boolean"`, and it treated `== true` as safe because it rejects
non-true values. It did not notice that "not true" here means "silently do
nothing" instead of an error. When CRF-089 was fixed, nobody grepped the other
`type: "boolean"` properties.

## Prevention

For every tool argument, check the declared JSON schema type at the start of
the tool, not only for arrays. Boolean arguments go through
`validate_booleans!`. When fixing an argument-type defect, grep every
`property ... type:` of that type in `lib/redmine_ai_helper/tools/` and fix
them all in the same change. Each test passes a value that Rails would cast to
the opposite meaning, or that a `== true` check would ignore.

**Promoted to**: Not yet
