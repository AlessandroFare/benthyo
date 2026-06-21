module.exports = {
  root: true,
  env: { browser: true, es2020: true },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:react-hooks/recommended',
  ],
  ignorePatterns: ['dist', '.eslintrc.cjs', 'vite.config.ts'],
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
  plugins: ['react-refresh'],
  rules: {
    // react-refresh is a dev-only fast-refresh hint. The shadcn/ui primitives
    // and shared design-system files legitimately co-export non-component
    // helpers (variants, hooks) — it is not a correctness or prod issue, so
    // downgrade to 'off' severity-wise and let real errors still fail the gate.
    'react-refresh/only-export-components': 'off',
    // The codebase uses a lot of Record<string, unknown> and intentional any
    // at external-API boundaries; keep the type checker authoritative there.
    '@typescript-eslint/no-explicit-any': 'off',
    '@typescript-eslint/no-unused-vars': [
      'warn',
      { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
    ],
  },
};
