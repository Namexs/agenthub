// Shared ESLint config for the Next.js app.
// Requires eslint-config-next in the consuming package.
module.exports = {
  extends: ['./base.cjs', 'next/core-web-vitals', 'prettier'],
  rules: {
    '@next/next/no-html-link-for-pages': 'off',
  },
};
