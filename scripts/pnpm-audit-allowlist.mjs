// pnpm audit with a documented allowlist (Phase G — final release
// remediation; allowlist emptied by the Next.js 15 upgrade).
//
// The 12 accepted Next.js 14.2.35 findings (3 CRITICAL + 9 HIGH,
// fixes only in Next.js 15.x/16.x — see agenthub-final-release/
// DEPENDENCY_REMEDIATION_REPORT.md §6) are GONE: the Next.js 15.5.29
// upgrade (see agenthub-next15-upgrade/NEXT15_UPGRADE_REPORT.md)
// removed every high/critical finding from the tree, so the
// allowlist below is currently EMPTY. The mechanism stays in place:
// deleting the audit job or lowering its level would hide future
// vulnerabilities, so this script runs the audit and fails ONLY on
// findings that are NOT explicitly allowlisted here.
//
// RULES (non-negotiable):
// - Every allowlist entry names the exact advisory (full GHSA id),
//   the package, and the reason it is accepted. No wildcards, no
//   severity-only blanket, no "ignore all of next".
// - Allowlisted findings are PRINTED on every run (visible, not
//   hidden) with their justification.
// - Any NEW high/critical finding fails the job (exit 1).
// - A STALE allowlist entry (an advisory that no longer appears in
//   the audit output — e.g. after upgrading Next.js) ALSO fails
//   the job, so the allowlist cannot rot: upgrade the dep, then
//   prune the entry in the same change.
// - If `pnpm audit` itself errors (registry unreachable, bad
//   response), the job fails loudly (exit 2) — it never passes
//   silently on a missing audit.
// - Moderate/low findings are counted and printed but do not fail,
//   matching the old `--audit-level=high` semantics.
//
// Usage in CI: `node scripts/pnpm-audit-allowlist.mjs`
// Local testing (pnpm audit is blocked on the dev VM — the npm
// registry audit endpoint returns 403 there): pass a fixture file
// instead of running the live audit:
//   node scripts/pnpm-audit-allowlist.mjs --audit-file scripts/pnpm-audit-allowlist.fixture.json
// The fixture path is test-only and must never be used in CI.
//
// Exit codes: 0 = pass; 1 = blocking findings or stale entries;
// 2 = the audit run itself failed or its output could not be parsed.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// --- The allowlist: currently EMPTY. ---
// The 12 Next.js 14.2.35 entries were pruned by the Next.js 15
// upgrade (Next.js 15.5.29 + React 19.3.1, 2026-11-19): the OSV
// re-audit of the new lockfile reports 0 CRITICAL and 0 HIGH
// findings, so every entry became stale and was removed in the same
// change (the script's own stale-entry rule requires this).
// Add an entry ONLY with a documented, independently justified risk
// acceptance, naming the exact advisory, package, and reason —
// no wildcards, no severity-only blanket, no "ignore all of next".
const ALLOWLIST = [];

const GATING = new Set(['critical', 'high']);

function fail(message, code) {
  console.error(`pnpm-audit-allowlist: ERROR: ${message}`);
  process.exit(code);
}

// --- Input: live audit, or a fixture file for local testing. ---
const args = process.argv.slice(2);
let auditJson;
const fixtureIdx = args.indexOf('--audit-file');
if (fixtureIdx !== -1) {
  const file = args[fixtureIdx + 1];
  if (!file) fail('missing value for --audit-file', 2);
  console.log(`(test mode: reading audit output from fixture ${file} — NOT a live audit)`);
  try {
    auditJson = JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    fail(`could not read/parse fixture ${file}: ${err.message}`, 2);
  }
} else {
  let raw;
  try {
    // pnpm audit exits non-zero when vulnerabilities are found — that
    // is the expected path, so capture stdout either way.
    raw = execFileSync('pnpm', ['audit', '--json'], {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (err) {
    raw = err.stdout?.toString() ?? '';
    if (!raw) fail(`pnpm audit failed to run: ${err.message}`, 2);
  }
  try {
    auditJson = JSON.parse(raw);
  } catch {
    fail('pnpm audit output was not valid JSON — the audit did not complete', 2);
  }
}

if (auditJson.error) {
  fail(
    `pnpm audit returned an error (${auditJson.error.code ?? 'unknown'}): ${auditJson.error.message ?? ''} — ` +
      'the audit did not run, so this job cannot pass.',
    2,
  );
}

const advisories = Object.values(auditJson.advisories ?? {});
if (advisories.length === 0 && !auditJson.metadata) {
  fail(
    'pnpm audit output has no advisories and no metadata — unexpected shape, refusing to pass',
    2,
  );
}

// --- Classify. ---
const byId = new Map(ALLOWLIST.map((entry) => [entry.id, entry]));
const allowlisted = [];
const blocking = [];
const nonGating = [];
const seenAllowlisted = new Set();

for (const adv of advisories) {
  const ghsa = adv.github_advisory_id ?? null;
  const severity = String(adv.severity ?? '').toLowerCase();
  const entry = ghsa ? byId.get(ghsa) : undefined;
  // An entry matches only when the package agrees too — the same GHSA
  // id on a different package is a different finding.
  if (entry && adv.module_name === entry.package) {
    seenAllowlisted.add(entry.id);
    allowlisted.push({ adv, entry });
  } else if (GATING.has(severity)) {
    blocking.push(adv);
  } else {
    nonGating.push(adv);
  }
}

const stale = ALLOWLIST.filter((entry) => !seenAllowlisted.has(entry.id));

// --- Report (everything is printed — nothing is hidden). ---
console.log(`\nDependency audit: ${advisories.length} advisories reported.`);
if (allowlisted.length > 0) {
  console.log(
    `\nAllowlisted (accepted risk, see DEPENDENCY_REMEDIATION_REPORT.md §6): ${allowlisted.length}`,
  );
  for (const { adv, entry } of allowlisted) {
    console.log(
      `  - ${entry.id} [${adv.severity}] ${adv.module_name}: ${entry.reason} (fixed in ${entry.fixedIn})`,
    );
  }
}
if (nonGating.length > 0) {
  const counts = {};
  for (const adv of nonGating) {
    const s = String(adv.severity ?? 'unknown').toLowerCase();
    counts[s] = (counts[s] ?? 0) + 1;
  }
  console.log(`\nNon-gating (moderate/low — counted, not failing): ${JSON.stringify(counts)}`);
}
if (blocking.length > 0) {
  console.log(`\nBLOCKING findings (high/critical, NOT allowlisted): ${blocking.length}`);
  for (const adv of blocking) {
    console.log(
      `  - ${adv.github_advisory_id ?? `npm:${adv.id}`} [${adv.severity}] ${adv.module_name}: ${adv.title ?? ''}`,
    );
  }
}
if (stale.length > 0) {
  console.log(`\nSTALE allowlist entries (no longer reported — prune them): ${stale.length}`);
  for (const entry of stale) {
    console.log(`  - ${entry.id} (${entry.package})`);
  }
}

// --- Verdict. ---
if (blocking.length > 0 || stale.length > 0) {
  console.log('\nAUDIT FAILED.');
  if (blocking.length > 0) {
    console.log(
      'Fix the blocking findings (upgrade the dependency), or — only with a documented, independently ' +
        'justified risk acceptance — add an entry to the ALLOWLIST in scripts/pnpm-audit-allowlist.mjs.',
    );
  }
  if (stale.length > 0) {
    console.log(
      'Remove the stale entries from the ALLOWLIST in scripts/pnpm-audit-allowlist.mjs (the advisory is ' +
        'gone — usually because the dependency was upgraded).',
    );
  }
  process.exit(1);
}
console.log('\nAUDIT PASSED: no new high/critical findings; all allowlist entries still apply.');
