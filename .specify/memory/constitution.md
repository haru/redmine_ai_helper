<!--
SYNC IMPACT REPORT
==================
Version change: (uninitialized template) → 1.0.0
Modified principles: N/A (initial creation)
Added sections:
  - Core Principles (5 principles)
  - Development Workflow
  - Code Standards
  - Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md  ✅ No structural change needed;
      "Constitution Check" section already uses placeholder that agents fill
      dynamically from this constitution at plan-time.
  - .specify/templates/spec-template.md  ✅ No change needed.
  - .specify/templates/tasks-template.md ✅ No change needed; task categories
      (TDD tests before implementation) align with Principle I.
Deferred TODOs: None.
-->

# Redmine AI Helper Plugin Constitution

## Core Principles

### I. Test-First Development (NON-NEGOTIABLE)

Test-Driven Development is mandatory without exception. The workflow MUST follow
Red → Green → Refactor in strict order:

- Tests MUST be written and confirmed failing before any implementation begins.
- Use `shoulda` (context/should blocks) for all test assertions — never rspec.
- Use `mocha` only for mocking external services (e.g., LLM APIs, Qdrant).
- Test coverage MUST reach 95% or higher (verified via `coverage/` directory).
- Test files MUST be located in `test/unit/` (models, agents, tools),
  `test/functional/` (controllers), or `test/integration/` (API-level tests).
- Use `test/model_factory.rb` for test fixtures; avoid raw ActiveRecord creation.

**Rationale**: Untested code is a liability in a plugin that interacts with
external AI APIs and modifies Redmine core behaviour. High coverage ensures
regressions surface before they reach production.

### II. Design Document Authority (NON-NEGOTIABLE)

Specifications in the `specs/` directory are AUTHORITATIVE and MANDATORY.

- Implementations MUST follow design documents exactly: architecture, file
  paths, method placement, public APIs, and test locations.
- Deviations from a design document MUST NOT be made without explicit user
  approval obtained before implementation begins.
- When a design appears incorrect, the agent MUST ask the user first rather
  than silently implementing a different approach.
- `CLAUDE.md` is a secondary authority for runtime development guidance and
  MUST be respected in the absence of a `specs/` document.

**Rationale**: Design authority prevents drift between intent and
implementation, especially in a multi-agent workflow where assumptions compound.

### III. Simplicity (YAGNI)

Only implement what is directly requested or demonstrably necessary.

- MUST NOT add features, refactor surrounding code, or make "improvements"
  beyond the stated task scope.
- MUST NOT implement fallback error handling — errors MUST surface immediately
  for proper diagnosis. Silent fallbacks are forbidden.
- MUST NOT add backwards-compatibility shims, re-exports, or deprecation
  stubs for removed code — delete cleanly.
- MUST NOT design for hypothetical future requirements.
- Three similar lines of code is preferable to a premature abstraction.
- Complexity beyond the minimum MUST be justified in the Complexity Tracking
  table of `plan.md`.

**Rationale**: Over-engineering obscures real behaviour and creates maintenance
debt in a codebase that must remain understandable for Redmine administrators.

### IV. Redmine Plugin Conventions

All code MUST integrate with Redmine's architecture and design system.

- **Ruby**: Follow Ruby on Rails conventions; write comments in English; use
  `ai_helper_logger` for logging — never `Rails.logger`.
- **JavaScript**: Use `let`/`const` (no `var`); vanilla JavaScript only
  (no jQuery); write comments in English.
- **CSS**: Use Redmine's class definitions exclusively; no custom colors or
  fonts; use `.box` for container elements.
- **Frontend security**: Build HTML in ERB templates, not JavaScript; JavaScript
  MUST only manipulate DOM elements already rendered by ERB.
- **Icons/i18n**: Use `sprite_icon` for icons; use `t()`/`l()` for
  internationalized text in templates.
- **Agents**: Inherit from `RedmineAiHelper::BaseAgent`; registration is
  automatic via the `inherited` hook — no manual registration.
- **Tools**: Defined via `RedmineAiHelper::BaseTools` DSL; override
  `available_tool_providers` to expose them to an agent.

**Rationale**: Redmine has its own conventions and design system. Violating
them produces UI inconsistency and upgrade incompatibility.

### V. Security-First Development

Security vulnerabilities MUST be treated as blocking defects.

- MUST NOT introduce XSS, SQL injection, command injection, or other OWASP
  Top 10 vulnerabilities.
- Disk file paths MUST NEVER be embedded in JSON text sent to LLMs; they MUST
  only be passed via RubyLLM's `with:` parameter or dedicated image tool
  parameters.
- Validate inputs at system boundaries (user input, external API responses);
  trust internal framework guarantees.
- If a security issue is discovered during implementation, STOP and fix it
  immediately before continuing.

**Rationale**: The plugin handles user-supplied content and passes data to
external AI services. A security failure could expose Redmine project data or
allow privilege escalation.

## Development Workflow

All feature work MUST follow this sequence:

1. Branch from `develop` using git-flow (`feature/`, `fix/`, etc.).
2. Create or update the specification in `specs/<###-feature-name>/spec.md`.
3. Write failing tests (Red phase) — get user confirmation before proceeding.
4. Implement minimum code to pass tests (Green phase).
5. Refactor while keeping tests green (Refactor phase).
6. Verify test coverage is 95%+ before requesting review.
7. Merge via PR targeting `develop`; `main` receives only production-ready releases.

**Commit messages** MUST be written in plain English. MUST NOT reference
Claude Code or any AI tooling in commit messages.

Design documents in `specs/` MUST be created or updated before implementation
begins for any non-trivial feature (see Principle II).

## Code Standards

| Area | Requirement |
|------|-------------|
| Ruby style | Rails conventions; English comments; `ai_helper_logger` only |
| JS style | `let`/`const`; no `var`; vanilla JS; English comments |
| CSS | Redmine design system only; no custom colors or fonts |
| Testing framework | `shoulda` assertions; `mocha` for external mocks |
| Coverage target | ≥ 95% (checked in `coverage/`) |
| Documentation | YARD for public APIs; `yard stats --list-undoc` to audit |
| File creation | Prefer editing existing files; create new files only when necessary |
| Error handling | Surface errors immediately; NEVER add silent fallbacks |

## Governance

This constitution supersedes all other practices and policies in this
repository. Where a conflict exists between this document and any other guide,
this document takes precedence.

**Amendment procedure**:
1. Propose the amendment with rationale in a PR description or design doc.
2. Obtain explicit user/maintainer approval before merging.
3. Provide a migration plan for any principle change that affects existing code.
4. Increment `CONSTITUTION_VERSION` following semantic versioning:
   - MAJOR: Backward-incompatible principle removal or redefinition.
   - MINOR: New principle or materially expanded guidance.
   - PATCH: Clarification, wording, or non-semantic refinements.
5. Update `LAST_AMENDED_DATE` to the date of the change (ISO 8601).

**Compliance review**: Every PR MUST include a Constitution Check that verifies
the implementation does not violate any principle. The Constitution Check
section in `plan.md` serves this purpose for planned features.

For runtime development guidance not covered by this constitution, refer to
`CLAUDE.md`.

**Version**: 1.0.0 | **Ratified**: 2026-02-27 | **Last Amended**: 2026-02-27
