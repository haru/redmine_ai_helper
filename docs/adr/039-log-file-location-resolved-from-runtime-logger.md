# ADR-039: The Redmine Log File Is Resolved from the Running Rails.logger

**Date**: 2026-09-23
**Status**: Accepted

## Context

Feature 060 lets administrators read the Redmine application log from the AI Helper chat and the MCP server (`SystemTools#get_log_file_info`, `#read_log_tail`, `#search_log`). The specification requires the tools to read the file that Redmine *actually* writes (FR-003), to report the log as unavailable when Redmine does not write to a file (FR-005), and never to fall back silently to some other file (FR-021). The path must also never come from user or LLM input (FR-006).

Redmine installations change the log destination in several ways:

- The Rails default: `ActiveSupport::Logger.new(config.default_log_file)`, which is `log/<env>.log` under `config.paths["log"]`.
- `RAILS_LOG_TO_STDOUT`, which `config/environments/production.rb` uses to send the log to standard output.
- `config/additional_environment.rb`, where administrators commonly set `config.logger = Logger.new("/var/log/redmine/redmine.log")` or a syslog logger.

Rails 8.1 always wraps the resulting logger in `ActiveSupport::BroadcastLogger`. `default_log_file` returns a `File` object rather than a path; logger 1.7.0 still records its path in `Logger::LogDevice#filename`, while IO streams such as `$stdout`, `$stderr` and `StringIO` leave `filename` as `nil`.

## Decision

**`RedmineAiHelper::Util::LogFileLocator.resolve("redmine")` inspects the running `Rails.logger` to find the file it writes to.**

1. If `Rails.logger` is an `ActiveSupport::BroadcastLogger`, its public `#broadcasts` are the candidates; otherwise `Rails.logger` itself is the only candidate.
2. For each candidate, the private `@logdev` instance variable of `::Logger` is read, and its public `LogDevice#filename` is used when present. A path that is not a regular file (for example `/dev/stdout`) is rejected by `LogFileReader` as unreadable.
3. The first file found is the Redmine log. If none is found, `UnavailableError` is raised with a reason that mentions `RAILS_LOG_TO_STDOUT` when that variable is set. The reason never contains a path.

## Consequences

- Every way of changing the log destination listed above is detected correctly, because the decision is based on where the logger writes rather than on configuration that may be overridden.
- `@logdev` is not a public API of the logger gem. A future logger or Rails release could rename it. `test/unit/util/log_file_locator_test.rb` builds real `ActiveSupport::Logger` instances over files, `StringIO`, `$stdout` and `$stderr`, so such a change is detected by the test suite.
- If the internals change without the tests being run, the locator finds no file and reports the log as unavailable. It never reads a wrong file.
- The AI Helper log is resolved differently (from `config/ai_helper/config.yml` through `CustomLogger.log_file_path`), because without a `logger` section it writes into `Rails.logger` and would be indistinguishable from the Redmine log.

## Alternatives Considered

- **`Rails.application.config.paths["log"].first` combined with `RAILS_LOG_TO_STDOUT`.** Rejected. A `config.logger` replaced in `additional_environment.rb` is not detected, so the tools would read a file that exists but is no longer written — the silent fallback FR-021 forbids.
- **A fixed `Rails.root.join("log", "#{Rails.env}.log")`.** Rejected for the same reason, and it also ignores changes to `paths["log"]`.
