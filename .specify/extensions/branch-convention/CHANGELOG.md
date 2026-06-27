# Changelog

## 1.0.0 (2026-04-08)

- Initial release
- Add `/speckit.branch-convention.configure` command for setting up naming rules
- Add `/speckit.branch-convention.validate` command for compliance checking
- Add `/speckit.branch-convention.rename` command for fixing non-compliant branches
- Built-in presets: default, gitflow, ticket, date, custom
- Template tokens: {seq}, {kebab}, {ticket}, {date}, {type}
- Optional `before_specify` hook for convention enforcement
- Addresses community request in issue #407 (39+ upvotes)
