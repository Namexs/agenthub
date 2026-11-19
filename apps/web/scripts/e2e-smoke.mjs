// E2E smoke test (Phase 8) — plain node script, Playwright via the
// `playwright` package (declared devDependency since Phase C — no
// manual symlinks; browsers installed via `npx playwright install
// chromium`).
//
// SCOPE (honest): unconnected-state render smoke only. There is no wallet
// in headless Chromium, so wallet connection, quest completion, and the
// attestation submit flow are NOT covered here — they are covered by the
// hook tests (mocked wagmi) and the anvil integration test (real chain).
// This script proves the production build serves every route without a
// crash and without console/page errors, and that the undeployed state
// renders the honest static catalogue (no fake "live" data).
//
// Usage: E2E_BASE_URL=http://127.0.0.1:3100 node scripts/e2e-smoke.mjs
// (run-e2e-smoke.sh builds + starts the server for you).

import { chromium } from 'playwright';

const BASE = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3100';

let passed = 0;
let failed = 0;
const failures = [];

function check(name, ok, detail = '') {
  if (ok) {
    passed += 1;
    console.log(`  PASS ${name}`);
  } else {
    failed += 1;
    failures.push(name);
    console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

const browser = await chromium.launch();
const page = await browser.newPage();
const pageErrors = [];
const consoleErrors = [];
page.on('pageerror', (err) => pageErrors.push(String(err)));
page.on('console', (msg) => {
  if (msg.type() === 'error') consoleErrors.push(msg.text());
});

async function goto(path) {
  const response = await page.goto(`${BASE}${path}`, { waitUntil: 'networkidle' });
  check(`GET ${path} -> ${response?.status()}`, response?.status() === 200);
  return response;
}

// --- Home ---
await goto('/');
check(
  'home shows the AGENTHUB intro',
  (await page.textContent('body'))?.includes('AGENTHUB is the activity and reputation hub') ??
    false,
);
check(
  'home shows the Connect button',
  (await page.getByRole('button', { name: 'Connect Binance Wallet' }).count()) === 1,
);

// --- Quests (undeployed: static catalogue + honest label) ---
await goto('/quests');
check('quests heading', (await page.locator('h1').textContent()) === 'Quests');
const questsBody = await page.textContent('body');
check(
  'quests shows the undeployed preview label',
  questsBody?.includes('Launch catalogue preview') ?? false,
);
check('quests shows the First Agent card', questsBody?.includes('First Agent') ?? false);
check('quests shows the Daily Check-in card', questsBody?.includes('Daily Check-in') ?? false);
check(
  'quests does NOT claim live data while undeployed',
  !(questsBody?.includes('Live quests from QuestManager') ?? true),
);

// --- Dashboard / Profile / Leaderboard / History / Campaigns / Security ---
for (const [path, heading] of [
  ['/dashboard', 'Dashboard'],
  ['/profile', 'Profile'],
  ['/leaderboard', 'Leaderboard'],
  ['/history', 'Activity History'],
  ['/campaigns', 'Community Campaigns'],
  ['/security', 'Security'],
]) {
  await goto(path);
  check(`${path} heading is "${heading}"`, (await page.locator('h1').textContent()) === heading);
}

// --- No JS errors anywhere on the visited pages ---
check('no page errors', pageErrors.length === 0, pageErrors[0] ?? '');
check('no console errors', consoleErrors.length === 0, consoleErrors[0] ?? '');

await browser.close();
console.log(`\nE2E smoke: ${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log(`Failures: ${failures.join(', ')}`);
  process.exit(1);
}
console.log('ALL E2E SMOKE CHECKS PASSED');
