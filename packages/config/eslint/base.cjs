// Shared ESLint base config (ESLint 8 legacy format).
// No framework-specific rules here; framework configs extend this file.
module.exports = {
  root: false,
  env: { es2022: true, node: true, browser: true },
  parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  extends: ['eslint:recommended', 'prettier'],
  rules: {
    'no-console': ['warn', { allow: ['warn', 'error'] }],
    'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    eqeqeq: ['error', 'always', { null: 'ignore' }],
  },
  overrides: [
    {
      files: ['*.ts', '*.tsx'],
      parser: '@typescript-eslint/parser',
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
      },
      plugins: ['@typescript-eslint'],
      extends: ['plugin:@typescript-eslint/recommended'],
      rules: {
        // Prefer the TS-aware variant over the base rule.
        'no-unused-vars': 'off',
        '@typescript-eslint/no-unused-vars': [
          'warn',
          { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
        ],
        '@typescript-eslint/no-explicit-any': 'warn',
      },
    },
  ],
};
