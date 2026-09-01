# ADR-020: The plugin logger falls back to Rails.logger when it cannot be built

**Date**: 2026-08-21
**Status**: Accepted

## Context

The project convention is unambiguous: plugin code logs through `ai_helper_logger`, never
through `Rails.logger` (constitution IV, `AGENTS.md`). `RedmineAiHelper::CustomLogger` reads
`{REDMINE_ROOT}/config/ai_helper/config.yml` the first time it is instantiated, so obtaining
the plugin logger is itself a configuration-dependent operation.

`RedmineAiHelper::Util::ConfigFile.autocompletion_settings` reads that same file and reports
every rejected value through the logger. When the file is unreadable, asking for the plugin
logger fails for exactly the reason the caller is trying to report, and that failure escapes
into the caller — which, for `autocompletion_settings`, means the issue and wiki edit screens
(`app/views/ai_helper/{shared,wiki}/_textarea_overlay.html.erb`) fail to render.

An earlier revision handled this in `ConfigFile` itself, with a `rescue` around
`ai_helper_logger.warn` that fell back to `Rails.logger`. That put a convention violation in
a caller, where the convention has no exceptions, and it made every future caller of
`ai_helper_logger` responsible for the same problem.

## Decision

**`RedmineAiHelper::Logger::ClassMethods#ai_helper_logger` returns `Rails.logger` when
`CustomLogger.instance` raises**, after recording why on `Rails.logger` itself.

1. `logger.rb` is the single place in the plugin that may reference `Rails.logger`. It already
   did — `CustomLogger#initialize` uses `Rails.logger` when the configuration has no `logger`
   section — so the boundary is unchanged, only widened to cover the failure case.
2. Callers keep writing `ai_helper_logger.warn`, with no `rescue` and no knowledge of the
   fallback. The convention "never `Rails.logger`" therefore holds literally everywhere else.
3. The reason for the fallback is logged (`"plugin logger unavailable (<class>: <message>)"`)
   instead of being swallowed, so a misconfigured plugin log is diagnosable.
4. The fallback is **not** memoized: `@ai_helper_logger ||=` is only assigned on success, so a
   later call retries `CustomLogger.instance` once the configuration is fixed.

## Consequences

**Positive**:

- Reading configuration can no longer take down an edit screen through the act of reporting a
  configuration problem.
- The rule stated in `AGENTS.md` is now true of all plugin code as written, rather than true
  except for one `rescue` clause a reader has to know about.
- The failure is visible. The previous `Rails.logger&.warn` discarded both the exception and,
  had `Rails.logger` been nil, the message.

**Negative**:

- `ai_helper_logger` no longer returns a `CustomLogger` unconditionally. Callers that need
  `CustomLogger`-specific behaviour (`set_log_level`) must ask for `CustomLogger.instance`
  directly. No caller does today.
- A `rescue StandardError` around logger construction is broad. It is deliberate: every reason
  the plugin log cannot be opened (`Psych::SyntaxError`, `Errno::EACCES`, `Errno::ENOSPC`) has
  the same correct answer, which is to keep running and say so elsewhere.

## Alternatives Considered

- **Keep the `rescue` in `ConfigFile` and record the deviation here** (rejected): the deviation
  would still be in caller code, and the next caller with the same circularity would either
  copy it or hit the original bug.
- **Let the failure propagate** (rejected): a syntax error in the plugin's own configuration
  file would make Redmine's issue edit screen return HTTP 500, which is out of proportion to
  the fault and to the feature involved.
- **Have `ConfigFile` skip logging when the logger is unavailable** (rejected): silent by
  construction, and the only signal about a broken configuration file would disappear.
