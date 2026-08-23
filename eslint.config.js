import js from "@eslint/js";
import globals from "globals";

export default [
  {
    files: ["assets/javascripts/**/*.js"],
    languageOptions: {
      sourceType: "script",
      globals: {
        ...globals.browser,
        // Supplied by ERB inline scripts, referenced as bare identifiers
        ai_helper_urls: "writable",
        // window.ai_helper is assigned (not declared with let/const/var), so
        // the bare identifier used throughout ai_helper.js needs a global.
        ai_helper: "writable",
        // Assigned via `window.AiHelperMarkdownParser = class {...}` (no local
        // declaration), then referenced as a bare identifier from other files.
        AiHelperMarkdownParser: "readonly",
        CommandCompletion: "readonly",
        // Redmine core globals (app/assets/javascripts/application-legacy.js),
        // referenced as bare identifiers from inline `onclick` bridges.
        toggleFieldset: "readonly",
        showAndScrollTo: "readonly",
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      "no-var": "error",
      "prefer-const": "error",
      // Callback signatures sometimes need a positional parameter that isn't
      // used (e.g. a shared callback shape); the codebase already marks
      // those with a leading underscore.
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],

      // Naming convention: everything is camelCase except the handful of
      // ERB<->JS bridge identifiers that intentionally mirror the Ruby/ERB
      // side's snake_case naming (see the `globals` block above and
      // AGENTS.md's ERB/JS separation guidelines).
      camelcase: [
        "error",
        {
          properties: "never",
          allow: ["^ai_helper$", "^ai_helper_urls$", "^ai_helper_generate_reply$"],
        },
      ],

      // Explicitness.
      eqeqeq: ["error", "smart"],
      curly: "error",
      "no-implicit-coercion": "error",

      // File/function size limits and complexity control.
      //
      // Ratchet, same policy as vitest.config.js's coverage threshold (see
      // ADR-023): these start near the codebase's current worst offenders
      // instead of an ideal target, so the rule doesn't fail CI outright on
      // adoption, and are only ever tightened (never loosened) as files and
      // functions get split up. See ADR-027 for the full rationale.
      // Baseline measured 2026-08-23:
      //   max-lines: 1092 (ai_helper_typo_checker.js) -> 1100
      //   max-lines-per-function: 418 (ai_helper_project_health.js) -> 420
      //   complexity: 30 (ai_helper_markdown_parser.js#processLists) -> 30
      //   max-depth: 6 (ai_helper.js#parseSSELines) -> 6
      //   max-params: 6 (ai_helper.js#parseSSELines) -> 6
      "max-lines": ["error", { max: 1100, skipBlankLines: true, skipComments: true }],
      "max-lines-per-function": ["error", { max: 420, skipBlankLines: true, skipComments: true }],
      complexity: ["error", 30],
      "max-depth": ["error", 6],
      "max-params": ["error", 6],
    },
  },
  {
    // AiHelperAutoCompletion/AiHelperAssignmentSuggestion are declared via
    // `class X {...}` in their own files (ai_helper_auto_completion.js,
    // ai_helper_assignment_suggestion.js) and referenced as bare identifiers
    // from these consuming files. Scoped here (not globally) so linting the
    // declaring files themselves doesn't conflict with their own class
    // declaration (no-redeclare).
    files: [
      "assets/javascripts/ai_helper_issue_autocompletion.js",
      "assets/javascripts/ai_helper_wiki_autocompletion.js",
    ],
    languageOptions: {
      globals: {
        AiHelperAutoCompletion: "readonly",
        AiHelperAssignmentSuggestion: "readonly",
      },
    },
  },
  {
    // AiHelperCollapsibleFieldset is declared via `const X = (() => {...})()`
    // in ai_helper_collapsible_fieldset.js and referenced as a bare
    // identifier from these consuming files. Scoped here for the same
    // no-redeclare reason as the block above.
    files: [
      "assets/javascripts/ai_helper_wiki_summary.js",
      "assets/javascripts/ai_helper_issue_summary.js",
    ],
    languageOptions: {
      globals: {
        AiHelperCollapsibleFieldset: "readonly",
      },
    },
  },
  {
    // getSummary/getWikiSummary are declared as `function` in
    // ai_helper_issue_summary.js/ai_helper_wiki_summary.js and referenced as
    // bare identifiers from ai_helper.js (contract B: existing page-scoped
    // global names, kept stable across the refactor). Scoped here so linting
    // the declaring files themselves doesn't conflict with their own
    // function declaration (no-redeclare).
    files: ["assets/javascripts/ai_helper.js"],
    languageOptions: {
      globals: {
        getSummary: "readonly",
        getWikiSummary: "readonly",
      },
    },
  },
  {
    files: ["test/javascript/**/*.js"],
    languageOptions: {
      sourceType: "module",
      globals: {
        ...globals.node,
        ...globals.browser,
        // Redmine core global, referenced directly by a couple of tests
        // that stub out AiHelperCollapsibleFieldset's real implementation.
        toggleFieldset: "readonly",
        describe: "readonly",
        it: "readonly",
        test: "readonly",
        expect: "readonly",
        vi: "readonly",
        beforeEach: "readonly",
        afterEach: "readonly",
        beforeAll: "readonly",
        afterAll: "readonly",
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      camelcase: ["error", { properties: "never" }],
      eqeqeq: ["error", "smart"],
      curly: "error",
      "no-implicit-coercion": "error",
      // Ratchet, same policy and baseline-measurement approach as the
      // assets/javascripts block above (see ADR-027). Baseline measured
      // 2026-08-23: max-lines 1493 (ai_helper_typo_checker.test.js) -> 1500,
      // complexity 12, max-depth 2, max-params 3 (all in helper functions,
      // not in `it`/`describe` bodies).
      //
      // max-lines-per-function is intentionally NOT enforced here: Vitest
      // files wrap their entire contents in one outer `describe()` callback
      // by design (see AGENTS.md's testing conventions), so that callback's
      // line count reflects the whole file, not a maintainability problem.
      "max-lines": ["error", { max: 1500, skipBlankLines: true, skipComments: true }],
      complexity: ["error", 12],
      "max-depth": ["error", 2],
      "max-params": ["error", 3],
    },
  },
  {
    ignores: [
      "node_modules/**",
      "coverage/**",
      "coverage-js/**",
      "app/views/**",
      "public/**",
      ".yardoc/**",
    ],
  },
];
