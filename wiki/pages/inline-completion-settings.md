---
title: Inline Completion Settings
type: component
sources: [S021, S022, S036]
updated: 2026-11-21
---

# Inline Completion Settings

Where `AiHelperAutoCompletion` reads its settings and how each value is validated. Split from [Inline Completion Request Flow](./inline-completion-request-flow.md).

## Settings source and validation

Completion settings are read through `ConfigFile.autocompletion_settings` from
`{REDMINE_ROOT}/config/ai_helper/config.yml` — the canonical `ConfigFile`
location. The two ERB overlays
(`app/views/ai_helper/{shared,wiki}/_textarea_overlay.html.erb`) previously did
an inline `YAML.load_file` against a **non-existent in-plugin path**, so
configured values never actually took effect (S021).

Validation runs on **every** call — the file is read again for each edit-screen
render and each completion request — with a warning log per rejected value
(S021):

| Key | Accepted | On absent/invalid |
|-----|----------|-------------------|
| `timeout` | number 1–600, truncated toward zero | warn + default `30` |
| `suggestion_color` | `#RGB` / `#RRGGBB` only | rejected |
| `debounce_delay` | number > 0 (0 rejected) | `nil` |
| `min_length`, `wiki_min_length` | non-negative **integer** (5.5 rejected) | `nil` |

`.inf` and `.nan` are numbers as far as YAML is concerned, but `to_i` raises on
them, so they are rejected like any other unusable value (S021).

`suggestion_color` needs a format check because the ERB interpolates it straight
into a **JS string literal**; making the config path real is what first made that
value injectable (S021). Returning `nil` for `debounce_delay` / `min_length`
preserves the per-view defaults — issue 500 ms, wiki 300 ms, `min_length` 5 —
which intentionally differ and must not change (S021). `wiki_min_length` falls
back to `min_length` when it is unset, so an installation that only sets
`min_length` gets that threshold in the wiki editor too (S021).

`ConfigFile.autocompletion_settings` treats an unparseable YAML file as `{}`
with a warning, so the edit screen still renders — `load_config` itself has no
such rescue and raises on invalid YAML or a non-Hash root. In practice a syntax
error still stops the instance from booting, because `init.rb` builds
`CustomLogger` at boot and that reads the same file through `load_config`
(S021). Reporting the problem cannot depend on the plugin logger for the same
reason, which is why `ai_helper_logger` falls back to `Rails.logger`
(ADR-020, S022). `CustomLogger`'s path rule now lives in
`CustomLogger.log_file_path(config)`; the path chosen at boot is exposed as
`CustomLogger#log_file_path` for the [log file
locator](./log-file-location-resolution.md) (S036).

## Related

- [Inline Completion Request Flow](./inline-completion-request-flow.md) — the main page.
