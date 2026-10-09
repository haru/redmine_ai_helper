# ADR-047: Version write tools reject disallowed sharing and non-editable custom fields

**Date**: 2026-10-08
**Status**: Proposed

## Context

Redmine's `VersionsController` and `Version#safe_attributes=` silently drop
values the current user may not set: a sharing scope outside
`allowed_sharings` and custom fields outside `editable_custom_field_values`.
For an AI agent this is dangerous. The tool call succeeds, the AI reports that
it set the value, and the value was never saved.

## Decision

`create_version` and `update_version` check the requested sharing against
`Version#allowed_sharings(User.current)` and the requested custom fields
against `Version#editable_custom_field_values(User.current)` before saving.
A value outside these sets is returned as an error that lists the allowed
values. `capable_version_props` exposes the same sets so the AI can check
them first. All other attribute validation is left to Redmine.

## Consequences

- The AI never believes a value was set when it was dropped.
- The same input that the Redmine REST API accepts silently can be an error here.
- The sharing and custom field rules stay in Redmine; the plugin only compares against them.
