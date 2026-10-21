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
- `initialize` (and therefore YAML loading) validates its boundary input with
  `ArgumentError`: `template` must be a String, `path` a String or nil,
  `input_variables` an Array of String or Symbol names that are valid
  placeholder names (`[A-Za-z_][A-Za-z0-9_]*`) and unique. The template and the
  normalized `input_variables` are frozen, so the declaration `format` checks
  cannot be changed after construction.
- `load_from_path` additionally requires the YAML root to be a mapping and reads
  `input_variables` with `fetch`, so a `null` value is rejected instead of
  becoming `[]`. Every such failure is logged with the file path before the
  `ArgumentError` (which names no path) is re-raised.
- `format` also rejects a String key and a Symbol key that name the same
  variable.
- `Llm#wiki_summary` and `Llm#project_health_report` no longer rescue
  `StandardError` and return `e.message`; like `Llm#issue_summary` they raise.
  The controller reports the failure on the stream (`generate_wiki_summary`,
  `generate_project_health`) or, for the REST API, in its existing error
  response, and never writes the message to the summary cache or the health
  report cache. `DocumentationAgent#backstory` now calls `format`, so the
  prompt text is sent instead of the template object.
- A test compares every shipped template's declared variables with the
  placeholders in its body, and runs the callers that build their variables
  inline against the real templates.

## Consequences

- A forgotten or misspelled variable fails before the prompt is built.
- The remaining broad `rescue` blocks in callers (chat, inline completion and
  typo check, assignment suggestion, `BaseAgent#dispatch`) still turn the new
  error into their usual failure result; this change does not alter them. The
  caller tests, which run the real templates through every caller, are what keep
  those paths from hiding a mismatch. Narrowing those rescues is a follow-up.
- A failure inside such a caller is logged more than once: `format` logs the
  path (only the template knows it) and the caller logs the exception.
- Template authors must keep `input_variables` in step with the body; the
  consistency test fails otherwise.
- The check relies on the declaration, not on scanning the body at run time.

## Alternatives Considered

- Extracting placeholders from the body at run time: the issue asks for a
  check against the declaration, and a scan with a loose pattern such as
  `\{[^}]+\}` would misread JSON examples. (The consistency test does scan the
  bodies, with the identifier-only pattern `\{[A-Za-z_][A-Za-z0-9_]*\}`, which the
  `{{ai_helper_chart(...)}}` directive does not match.)
- Logging a warning and continuing: the project forbids fallback error handling.
- A dedicated exception class: a standard `ArgumentError` matches the issue and
  the meaning of a keyword mismatch.
- Putting the file path in the error message: a caller's `rescue => e` can put
  `e.message` into a user-facing response or an LLM input.
