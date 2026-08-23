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
