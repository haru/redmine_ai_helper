# ADR-048: Version tools return user-caused failures as error results and raise system failures

**Date**: 2026-10-08
**Status**: Proposed

## Context

In chat, an exception raised by a tool stops the whole tool execution loop of
the agent (RubyLLM). When a user asks for several versions, one failure, such
as a duplicate name, prevents the rest from being processed, and the AI cannot
see why it failed.

## Decision

Failures caused by the user's input or situation (missing argument, not found,
not accessible, permission denied, validation error, version in use) are
returned as `{ error: "<message>" }`. System failures (database connection,
SQL errors, program bugs) are raised as before. The mechanism is
`BaseTools::UserError` and the private `BaseTools#user_errors_as_result`. Only
the four version functions (`capable_version_properties`, `create_version`,
`update_version`, `delete_version`) use it.

## Consequences

- A partial failure does not prevent the remaining requests from being processed.
- System failures still reach the logs and are not hidden from operators.
- The MCP behavior is unchanged in form: the error is returned as a text response with `isError: true`.
- Tools now report failures in two ways. Whether to extend this to other tools is a separate decision.
