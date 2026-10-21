# ADR-063: PromptTemplate#format requires the declared variables exactly

**Date**: 2026-10-21
**Status**: Accepted

## Context

`PromptTemplate#format` substituted whatever keyword arguments it received and
ignored `input_variables`. A caller that forgot a variable or misspelled its
name sent the raw `{variable}` placeholder to the LLM, with no error and no log
line (GitHub issue #533). Callers such as the inline completion agents also
rescue `StandardError` around `format`, so a failure there would have been
reported as an empty completion.

## Decision

- `format` compares the given keyword names with the template's declared
  `input_variables` (both normalized to strings) before any substitution. A
  missing or unknown name raises one standard `ArgumentError` that lists both
  kinds, for example `Missing prompt variables: a; unknown prompt variables: b`.
- The error message carries variable names only. A template loaded from a YAML
  file remembers its `path`; `format` writes the path and the names to
  `ai_helper_logger.error` before raising, so a disk path never reaches a
  user-facing response or an LLM input through a caller's `rescue => e`.
- `initialize` (and therefore YAML loading) rejects an `input_variables` value
  that is not an Array, or that holds anything other than String or Symbol
  elements, with `ArgumentError`.
- A test compares every shipped template's declared variables with the
  placeholders in its body, and runs the callers that build their variables
  inline against the real templates.

## Consequences

- A forgotten or misspelled variable fails before the prompt is built.
- Existing broad `rescue` blocks in callers still turn the new error into their
  usual failure result; this change does not alter them. The caller tests are
  what keep those paths from hiding a mismatch.
- Template authors must keep `input_variables` in step with the body; the
  consistency test fails otherwise.
- The check relies on the declaration, not on scanning the body at run time.

## Alternatives Considered

- Extracting placeholders from the body at run time: it differs from the
  declaration-based expectation in the issue and misreads `{...}` inside JSON
  examples such as the chart directive in the comparison prompt.
- Logging a warning and continuing: the project forbids fallback error handling.
- A dedicated exception class: a standard `ArgumentError` matches the issue and
  the meaning of a keyword mismatch.
- Putting the file path in the error message: a caller's `rescue => e` can put
  `e.message` into a user-facing response or an LLM input.
