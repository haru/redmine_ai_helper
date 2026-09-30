# ADR-042: Model Profile Temperature Is Optional

**Date**: 2026-09-30
**Status**: Accepted

## Context

The model profile's Temperature field is currently mandatory: the model validates
its presence, the database column defaults to 0.5, the new-profile form marks the
field as required, and the connection test silently substitutes 1.0 when the
field is left blank. Recent models, however, reject or deprecate the temperature
parameter (for example, Anthropic's `claude-sonnet-5-5` responds with
"`temperature` is deprecated for this model"). For such models the plugin's
mandatory temperature makes the profile effectively unusable (Issue #465):
the connection test fails on the forced value, and the profile cannot even be
saved with an empty field.

## Decision

Temperature is an optional field. When it is unset, the plugin does not
substitute any value: AI requests are sent without a temperature parameter and
the AI service's own default applies.

Concretely:

- The model validation drops `presence` and keeps the numerical check
  (`>= 0.0`) with `allow_nil: true`. Empty and whitespace-only inputs are stored
  as `nil` by Rails' float type conversion; `0` is stored as `0.0` and remains
  distinct from unset.
- A migration removes the `0.5` column default so new profiles start unset.
  Existing rows keep their stored values.
- The connection test no longer fills in `1.0` for a blank field.
- The form no longer marks the Temperature field as required.
- The LLM client layer is unchanged: `create_chat` already skips
  `chat.with_temperature(...)` when the profile's temperature is `nil`, for
  every provider.
- The GPT-5 series auto-correction (forcing temperature to 1.0 on save) is kept
  unchanged, because those models require a fixed temperature.

## Consequences

- Profiles for temperature-rejecting models can be saved and used without
  temperature-related errors.
- Requests for unset profiles omit the parameter entirely, so behaviour is
  governed by each AI service's default. This is the plugin-wide contract for
  any future per-model handling built on top of it.
- Existing profiles keep working with their configured values (no data change
  at upgrade time).
- Invalid input (negative or non-numeric values) is still rejected, so input
  boundary validation is preserved.

## Alternatives Considered

- **Substitute a service-specific default when unset** (the previous
  connection-test behaviour, `temperature ||= 1.0`): rejected because it
  triggers the very "temperature is deprecated" errors this change removes, and
  contradicts the principle that the plugin should not invent request
  parameters the administrator left blank.
- **Disable the field automatically for models known to reject temperature**:
  rejected as out of scope (YAGNI); it would require maintaining a per-model
  capability table and does not generalise across providers.
- **Reset existing profiles to unset during the migration**: rejected because
  silently changing administrators' configured values would be a breaking
  regression.
