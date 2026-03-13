# Tool Development Guidelines

## nil Check for Tool Parameters

Always validate tool parameters for nil values, even when marked `required: true`.

**Reason**: LLMs occasionally generate nil values for required fields. Tool implementations must handle this defensively rather than relying on the `required` annotation alone.

### When to raise an error vs. skip

- **Raise an error** if the field is essential for the operation to make sense (e.g., `issue_id` in `update_issue` — there is nothing to update without it).
- **Skip and warn** if the operation can proceed meaningfully without the field (e.g., `field_id` in a `custom_fields` entry — the issue can still be created/updated, just without that custom field).

### Implementation pattern

```ruby
# Required field where nil makes the operation impossible → raise
raise "field_name is required" if field_name.nil?

# Required field where nil can be safely skipped → warn and skip
if field[:field_id].nil?
  ai_helper_logger.warn "Skipping custom field with nil field_id"
  next
end

# Optional field → silent skip
issue.priority_id = priority_id if priority_id
```

### Logging

- Use `ai_helper_logger.warn` when skipping a field that was declared `required: true`.
- No logging needed when skipping fields declared `required: false`.
- Never use `Rails.logger`.
