# ADR-026: Shared JS Helper Extraction Threshold

**Date**: 2026-08-22
**Status**: Accepted

## Context

When extracting inline JavaScript from ERB templates, some code patterns appeared in multiple templates. A threshold was needed to decide when to extract shared helper functions versus keeping code co-located with its feature module.

Three categories of duplication were identified:

1. **Collapsible fieldset open/close + localStorage persistence** — 3 occurrences (`wiki/_summary`, `issues/_form`, `issues/_bottom`), all sharing an undeclared `isOpen` variable bug.
2. **Typo checker overlay initialization** (11 item labels + `new AiHelperTypoChecker(...)`) — 4 occurrences (`wiki/_typo_overlay`, `wiki/_textarea_overlay`, `shared/_textarea_overlay` used in 2 contexts).
3. **Health report Markdown parse + export** — 2 occurrences (`project/_health_report_detail_pane`, `project/_health_report_show`), nearly 100% identical code.

Additionally, some extracted code needed to be appended to existing `.js` files (`ai_helper_typo_checker.js`, `ai_helper_sub_issues.js`, `ai_helper_project_health.js`) rather than creating new files. A prior refactor (issue-046) had established a rule that existing JS files themselves must not be refactored.

## Decision

### Duplication threshold

Code is extracted into a shared helper when it meets **either** condition:

- **3+ occurrences** of the same pattern across ERB templates (constitution principle III: DRY).
- **2 occurrences** of substantively identical code (copy-paste with only variable names changed).

Code appearing exactly twice with meaningful differences remains in its feature-specific module.

### Shared helper locations

| Shared pattern | Location | Rationale |
|---|---|---|
| Collapsible fieldset | New file `ai_helper_collapsible_fieldset.js` | No existing file owns this concern |
| Typo checker init factory | Appended to existing `ai_helper_typo_checker.js` | Same responsibility domain; factory is an extension, not a refactor of existing code |
| Health report Markdown export | Appended to existing `ai_helper_project_health.js` | Same responsibility domain; identical code already logically belongs here |

### Appending to existing 046 files does not violate the scope exclusion

Issue-046's scope exclusion states: "existing JS files themselves must not be refactored." This means rewriting or restructuring existing code within those files is prohibited. Appending **new** code (moved from ERB) to the end of these files does not modify the existing code and therefore does not violate the constraint. The 3-step process (mechanical move → characterization test → convention cleanup) applies only to the newly appended code.

## Consequences

- **Positive**: Three duplication clusters are consolidated, reducing the surface area for future bugs (e.g., the shared `isOpen` bug is fixed once in the collapsible fieldset helper).
- **Positive**: The 3-occurrence threshold is objective and auditable, preventing premature or excessive abstraction.
- **Negative**: The 2-occurrence exception for "substantively identical" code introduces mild subjectivity. The health report export is the only case that triggers this exception.
- **Negative**: Appended code in existing files creates files with mixed provenance (046 original + 047 appended). Comments delineate the boundary.

## Alternatives Considered

- **Strict 1 ERB = 1 new JS file**: Rejected. Would duplicate the typo checker initialization 4 times and the health report export 2 times, violating DRY and quadrupling the convention cleanup effort.
- **Extract all shared code into separate new files only**: Rejected for typo checker and project health cases. The duplicated code logically belongs to the same module, and splitting it into a separate file would create an unnatural separation. The collapsible fieldset case (no existing owner) correctly gets a new file.