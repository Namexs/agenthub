// Dependency audit via the OSV API (Phase 4).
//
// `pnpm audit` cannot run on the dev VM: the registry's audit endpoint
// returns 403 policy_denied (see CI_EVIDENCE.md §3). This script is the
// local substitute — it reads every name@version from pnpm-lock.yaml
// and queries https://api.osv.dev/v1/querybatch (the same GitHub
// Advisory Database that backs npm audit). It does NOT replace the CI
// audit job (pnpm audit --audit-level=high on GitHub runners); it is
// the evidence that the locked tree was checked on 2026-11-19.
//
// Usage: node scripts/osv-audit.mjs [path/to/pnpm-lock.yaml]
// Output: human summary on stdout; full JSON written next to the
// lockfile's repo logs dir when run from the repo root (see below).

import { readFileSync, writeFileSync } from 'node:fs';

const lockfilePath = process.argv[2] ?? 'pnpm-lock.yaml';
const text = readFileSync(lockfilePath, 'utf8');

// --- Parse the `packages:` section (lockfile v9) ---
// Keys look like:   '@scope/name@1.2.3':   or   name@1.2.3:
// (quoted when the name starts with @; peer suffixes in parens are
// stripped; the same name@version can appear with several peer sets.)
const lines = text.split('\n');
const packagesStart = lines.findIndex((l) => l === 'packages:');
const snapshotsStart = lines.findIndex((l) => l === 'snapshots:');
if (packagesStart < 0 || snapshotsStart < packagesStart) {
  console.error('could not find the packages: section in the lockfile');
  process.exit(2);
}
const seen = new Map(); // "name@version" -> { name, version }
for (const line of lines.slice(packagesStart + 1, snapshotsStart)) {
  const m = /^  '?([^':]+)'?:$/.exec(line);
  if (!m) continue;
  let key = m[1];
  const paren = key.indexOf('(');
  if (paren >= 0) key = key.slice(0, paren);
  const at = key.lastIndexOf('@');
  if (at <= 0) continue;
  const name = key.slice(0, at);
  const version = key.slice(at + 1);
  if (!/^\d+\.\d+\.\d+/.test(version)) continue; // skip non-semver (file:/link:)
  seen.set(`${name}@${version}`, { name, version });
}
const packages = [...seen.values()];
console.log(`packages in lockfile: ${packages.length}`);

// --- Query OSV in batches of 500 (API limit is 1000) ---
const findings = []; // { pkg, version, id, summary, severity, aliases, fixed }
for (let i = 0; i < packages.length; i += 500) {
  const batch = packages.slice(i, i + 500);
  const res = await fetch('https://api.osv.dev/v1/querybatch', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      queries: batch.map((p) => ({
        package: { name: p.name, ecosystem: 'npm' },
        version: p.version,
      })),
    }),
  });
  if (!res.ok) {
    console.error(`OSV querybatch failed: HTTP ${res.status}`);
    process.exit(2);
  }
  const { results } = await res.json();
  results.forEach((r, j) => {
    if (!r.vulns) return;
    const pkg = batch[j];
    for (const v of r.vulns) {
      const severity =
        v.database_specific?.severity ?? (v.severity?.length ? 'CVSS (see JSON)' : 'UNKNOWN');
      const fixed = new Set();
      for (const a of v.affected ?? []) {
        if (a.package?.name !== pkg.name) continue;
        for (const range of a.ranges ?? []) {
          for (const e of range.events ?? []) {
            if (e.fixed) fixed.add(e.fixed);
          }
        }
      }
      findings.push({
        pkg: pkg.name,
        version: pkg.version,
        id: v.id,
        summary: v.summary ?? '',
        severity,
        aliases: v.aliases ?? [],
        fixed: [...fixed].sort(),
      });
    }
  });
  console.log(`queried ${Math.min(i + 500, packages.length)}/${packages.length}`);
}

// --- Enrich: querybatch returns only vuln IDs, so fetch the full
// record per unique ID (65 in this tree) for severity/summary/fixes. ---
const uniqueIds = [...new Set(findings.map((f) => f.id))];
const details = new Map();
for (let i = 0; i < uniqueIds.length; i += 10) {
  const chunk = uniqueIds.slice(i, i + 10);
  const fetched = await Promise.all(
    chunk.map(async (id) => {
      const res = await fetch(`https://api.osv.dev/v1/vulns/${id}`);
      if (!res.ok) return [id, null];
      return [id, await res.json()];
    }),
  );
  for (const [id, v] of fetched) details.set(id, v);
}
for (const f of findings) {
  const v = details.get(f.id);
  if (!v) continue;
  f.summary = v.summary ?? '';
  f.aliases = v.aliases ?? [];
  f.severity = v.database_specific?.severity ?? 'UNKNOWN';
  const fixed = new Set();
  for (const a of v.affected ?? []) {
    if (a.package?.name !== f.pkg) continue;
    for (const range of a.ranges ?? []) {
      for (const e of range.events ?? []) {
        if (e.fixed) fixed.add(e.fixed);
      }
    }
  }
  f.fixed = [...fixed].sort();
}

// --- Summary ---
const bySeverity = {};
for (const f of findings) {
  const s = String(f.severity).toUpperCase();
  bySeverity[s] = (bySeverity[s] ?? 0) + 1;
}
console.log(`\nfindings: ${findings.length}`);
console.log(`by severity: ${JSON.stringify(bySeverity)}`);
const highPlus = findings.filter((f) =>
  ['CRITICAL', 'HIGH'].includes(String(f.severity).toUpperCase()),
);
highPlus.sort((a, b) => `${a.pkg}${a.id}`.localeCompare(`${b.pkg}${b.id}`));
console.log(`\nHIGH/CRITICAL findings (${highPlus.length}):`);
for (const f of highPlus) {
  console.log(
    `- ${f.severity} ${f.id} ${f.aliases.join(',')} — ${f.pkg}@${f.version}` +
      ` (fixed in: ${f.fixed.join(', ') || 'none listed'}) — ${f.summary}`,
  );
}
const outPath = 'agenthub-final-pretestnet/logs/phase4-osv-audit.json';
try {
  writeFileSync(outPath, JSON.stringify({ packages: packages.length, findings }, null, 2));
  console.log(`\nfull JSON written to ${outPath}`);
} catch {
  console.log('\ncould not write JSON next to the repo logs (run from the repo root to save it)');
}
