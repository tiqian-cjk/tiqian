// Strict lint for this package: `any` and `as unknown` are banned outright,
// and the two rules carrying that ban cannot be disabled inline.

import eslint from "@eslint/js";
import comments from "@eslint-community/eslint-plugin-eslint-comments";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "lib/",
      "shared/",
      "node_modules/",
      "pack-output/",
      "platforms/",
      "package-lock.json",
      "cargo.log",
    ],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    // The manifest swap script is plain ESM; it only touches these Node
    // globals.
    files: ["*.mjs"],
    languageOptions: {
      globals: { console: "readonly", process: "readonly" },
    },
  },
  {
    linterOptions: {
      reportUnusedDisableDirectives: "error",
    },
    plugins: { "@eslint-community/eslint-comments": comments },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "no-restricted-syntax": [
        "error",
        {
          selector: "TSAsExpression[typeAnnotation.type='TSAnyKeyword']",
          message: "`as any` is not allowed; give the value a real type.",
        },
        {
          selector: "TSAsExpression[typeAnnotation.type='TSUnknownKeyword']",
          message:
            "`as unknown` is not allowed; cast directly to the target type or narrow it.",
        },
      ],
      "@eslint-community/eslint-comments/no-restricted-disable": [
        "error",
        "@typescript-eslint/no-explicit-any",
        "no-restricted-syntax",
      ],
    },
  },
);
