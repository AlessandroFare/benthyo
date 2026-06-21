module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: {
    sourceType: 'module',
  },
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
  ],
  env: { node: true, jest: true, es2022: true },
  ignorePatterns: ['.eslintrc.cjs', 'dist', 'node_modules'],
  rules: {
    // NestJS DI + external-API boundaries use intentional any; the type
    // checker is authoritative there.
    '@typescript-eslint/no-explicit-any': 'off',
    '@typescript-eslint/no-unused-vars': [
      'warn',
      { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
    ],
    // Decorator metadata + DI make this rule noisy and unhelpful here.
    '@typescript-eslint/no-useless-constructor': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
  },
};
