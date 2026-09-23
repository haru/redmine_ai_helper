---
title: Log File Location Resolution
type: decision
sources: [S036]
updated: 2026-09-23
---

# Log File Location Resolution

How the [log file access tools](./log-file-access-tools.md) decide *which file*
is "the Redmine log" and "the AI Helper log". The LLM and the user never
supply a path: the file is derived only from `log_type` (`"redmine"` or
`"ai_helper"`), so path traversal is impossible (S036). Resolution lives in
`RedmineAiHelper::Util::LogFileLocator`; ADR-039 records the Redmine-side
decision (S036).

## Redmine log: ask the runtime logger

**Decision**: inspect the live `Rails.logger` and read the file it actually
writes to (S036):

1. If `Rails.logger` is an `ActiveSupport::BroadcastLogger`, walk its public
   `#broadcasts`; otherwise use `[Rails.logger]`. Rails 8.1 wraps the logger in a
   `BroadcastLogger` at boot, so the walk is required (S036).
2. From each candidate, take `::Logger`'s internal `@logdev`
   (`Logger::LogDevice`) and use `LogDevice#filename`; the first file found wins
   (S036).
3. No file → "not accessible" with a reason: `RAILS_LOG_TO_STDOUT` set →
   "logging to stdout"; otherwise "Redmine's logger does not write to a file
   (syslog, stderr, …)" (S036).

This handles a `config.logger` swapped in `config/additional_environment.rb` and
the `RAILS_LOG_TO_STDOUT` branch of `production.rb` with no special cases,
because it reads what is really in use (S036).

**Gotcha — `@logdev` is private.** It is not public API; only
`LogDevice#filename` / `#dev` are public readers (logger 1.7.0). The dependency
is pinned by unit tests that build real `ActiveSupport::Logger`s over a File,
StringIO and STDOUT, so a gem change that breaks it fails a test rather than
silently reading the wrong file. If it does break at runtime, the result is
"not accessible", never a wrong file (S036).

**Correction found during implementation**: the plan assumed Rails'
`default_log_file` (a `File` object, not a path) leaves `LogDevice#filename`
`nil`, requiring a fallback to `LogDevice#dev.path`. In logger 1.7.0 `filename`
*is* set for `File` objects — it is `nil` only for `$stdout`, `$stderr` and
`StringIO` — so the fallback was unreachable and only `filename` is used.
Non-regular paths such as `/dev/stdout` are rejected later by the
[reader](./log-file-reader.md) as unreadable (S036).

**Rejected**: guessing from `config.paths["log"].first` + `RAILS_LOG_TO_STDOUT`,
or hard-coding `log/#{Rails.env}.log` — both miss a replaced `config.logger` and
can read a file that exists but is not being written, which the spec forbids
("never implicitly read a substitute file") (S036).

## AI Helper log: share the logger's own rule

**Decision**: extract the path rule from `CustomLogger#initialize` into
`CustomLogger.log_file_path(config)`, called by both the logger and the locator,
so the two can never drift apart (S036):

| `config/ai_helper/config.yml` | Log file |
|---|---|
| no `logger` section | none — `CustomLogger` writes to `Rails.logger`; "not accessible", reason "AI Helper logs go to the Redmine log" |
| `logger.file` set | `Rails.root.join("log", file)` |
| `logger` without `file` | `Rails.root.join("log/ai_helper.log")` |

`CustomLogger` uses `::Logger.new(path, "daily")`, which renames the current
file to `…YYYYMMDD` and reopens the same path, so the current file is always the
path above; rotated files are out of scope (S036).

**Rejected**: inspecting `CustomLogger.instance` at runtime — with no `logger`
section it returns `Rails.logger`, indistinguishable from the Redmine log;
reading `log/ai_helper.log` when the section is absent — that file may be a
stale leftover (S036).

## Related

- [Log File Access Tools](./log-file-access-tools.md) ·
  [Log File Reader](./log-file-reader.md)
- [Inline Completion Request Flow](./inline-completion-request-flow.md) — why
  `ai_helper_logger` falls back to `Rails.logger` (ADR-020).
