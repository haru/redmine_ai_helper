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
        getSummary: "readonly",
        getWikiSummary: "readonly",
        // window.ai_helper is assigned (not declared with let/const/var), so
        // the bare identifier used throughout ai_helper.js needs a global.
        ai_helper: "writable",
        // Assigned via `window.AiHelperMarkdownParser = class {...}` (no local
        // declaration), then referenced as a bare identifier from other files.
        AiHelperMarkdownParser: "readonly",
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
    files: ["test/javascript/**/*.js"],
    languageOptions: {
      sourceType: "module",
      globals: {
        ...globals.node,
        ...globals.browser,
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
