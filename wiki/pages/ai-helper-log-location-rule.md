---
title: AI Helper Log Location Rule
type: decision
sources: [S036]
updated: 2026-11-21
---

# AI Helper Log Location Rule

How the AI Helper log path shares the logger's own rule. Split from [Log File Location Resolution](./log-file-location-resolution.md).

## AI Helper log: share the logger's own rule

**Decision**: extract the path rule from `CustomLogger#initialize` into
`CustomLogger.log_file_path(config)`. The logger applies it once at boot and
keeps the result in `CustomLogger#log_file_path`, which the locator reads, so
the tools follow the file the running logger writes even if `config.yml` is
edited without a restart (S036):

| `config/ai_helper/config.yml` | Log file |
|---|---|
| no `logger` section | none — `CustomLogger` writes to `Rails.logger`; "not accessible", reason "AI Helper logs go to the Redmine log" |
| `logger.file` set | `Rails.root.join("log", file)` |
| `logger` without `file` | `Rails.root.join("log/ai_helper.log")` |

`CustomLogger` uses `::Logger.new(path, "daily")`, which renames the current
file to `…YYYYMMDD` and reopens the same path, so the current file is always the
path above; rotated files are out of scope (S036).

A `config.yml` that could not be read at boot leaves no logger instance; the
locator then reports the log as unavailable without the path of `config.yml`.

**Rejected**: inspecting the `::Logger` wrapped by `CustomLogger.instance` — with
no `logger` section it is `Rails.logger`, indistinguishable from the Redmine log;
re-reading `config.yml` on every call — after an edit without a restart it names
a file the logger does not write; reading `log/ai_helper.log` when the section is
absent — that file may be a stale leftover (S036).

## Related

- [Log File Location Resolution](./log-file-location-resolution.md) — the main page.
