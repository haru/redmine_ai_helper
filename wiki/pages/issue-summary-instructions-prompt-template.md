---
title: "Issue Summary Instructions: Prompt Template & Settings"
type: decision
sources: [S035]
updated: 2026-09-20
---

# Issue Summary Instructions: Prompt Template & Settings

Companion page to
[Issue Summary Instructions & Role Gating](./issue-summary-instructions-role-gating.md),
which covers how roles are resolved and when they're attached. This page
covers how the new `issue_summary_instructions` setting reaches the prompt,
its name, and why no other subsystem needs to change (S035).

## Decision: keep the prompt-diff at zero via a separate, conditionally-concatenated template

`summary.yml` / `summary_ja.yml` are **not modified**. The additional
instructions section lives in new templates —
`assets/prompt_templates/issue_read_agent/summary_instructions{,_ja}.yml` —
and Ruby only concatenates that rendered section onto the formatted prompt
when the project's `issue_summary_instructions` is present (S035).

`PromptTemplate#format` (`lib/redmine_ai_helper/util/prompt_template.rb:35-42`)
does plain `{key}` substitution; adding a `{issue_summary_instructions}`
placeholder to the existing template and passing an empty string would leave
the surrounding newlines behind, so the prompt would never byte-for-byte
match the pre-feature output for projects with no instructions set. Keeping
the base template untouched makes that invariant a one-line
`assert_equal` in tests (S035).

Locale resolution rides the existing
`PromptLoader.load_template` (`lib/redmine_ai_helper/util/prompt_loader.rb:14-24`),
so the Japanese section resolves the same way `summary_ja.yml` already does —
no new locale-handling code (S035).

### Rejected alternatives

- Adding a placeholder to the existing template — breaks the zero-diff
  invariant for unset projects, as above (S035).
- Two full template variants (with/without instructions) — duplicates the
  summary format rules in two places; a fix to one could miss the other
  (DRY violation) (S035).
- Hardcoding the section text in Ruby — no path to a Japanese version, and
  breaks from the plugin's existing convention of keeping prompt text in
  templates (S035).

## Decision: column name `issue_summary_instructions`

The plugin already has a *wiki page* summary feature
(`assets/prompt_templates/wiki_agent/summary.yml`), so a bare
`summary_instructions` would be ambiguous about which summary it configures.
`issue_summary_instructions` follows the existing
`<target>_<purpose>_instructions` shape also used by `issue_draft_instructions`
(S035).

`summary_instructions` (ambiguous) and `issue_summary_prompt` (breaks the
`_instructions` suffix convention of the other four settings) were rejected
(S035).

## Decision: no cache invalidation on save

`AiHelperSummaryCache` is keyed by `object_class`/`object_id` (per issue),
and `AiHelperProjectSettingsController#update` only persists settings — it
never touches the cache. So changing a project's
`issue_summary_instructions` does not need new cache-busting code; this is
satisfied by not implementing anything, with a regression test to keep it
that way (S035).

## Settings pattern reused

The new setting follows the same five-touch-point pattern as
`assignment_suggestion_instructions` (the most recently added sibling
setting): a `text` column migration on `ai_helper_project_settings`, a
Strong Parameters entry in `ai_helper_project_settings_controller.rb`, a
`text_area` in `_show.html.erb`, an `en.yml`/`ja.yml` label pair, and a read
site in `issue_read_agent.rb`. `AiHelperProjectSetting` needs no change — it
has no validations or `attr_accessible` list to extend (S035).

## Related

- [Issue Summary Instructions & Role Gating](./issue-summary-instructions-role-gating.md) —
  the `Member`-based role resolution and the gating rule this template feeds.
- [Issue AI Features](./issue-ai-features.md) — where `issue_summary` and the
  other `IssueReadAgent` features live.
