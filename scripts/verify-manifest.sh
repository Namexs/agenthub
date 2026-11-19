#!/usr/bin/env bash
# Verify the commit recorded in PACKAGE_MANIFEST.md.
# - Every file hash in the manifest is recomputed from the RECORDED
#   COMMIT's tree (git cat-file) and compared — this verifies the commit,
#   not the working tree, so it works from any checkout that contains the
#   manifest and the git history. HEAD does not need to equal the recorded
#   commit (the manifest is committed separately from the commit it
#   describes, so HEAD is normally a descendant of it).
# - Submodule commits are compared against the recorded commit's gitlinks.
# Exit 0 = the recorded commit matches the manifest; exit 1 = any mismatch.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MANIFEST="PACKAGE_MANIFEST.md"
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST not found in this checkout"; exit 1; }

FAILURES=0

RECORDED="$(grep -m1 '^- Commit: `' "$MANIFEST" | sed -E 's/^- Commit: `([0-9a-f]+)`.*/\1/')"
if ! git cat-file -t "$RECORDED" >/dev/null 2>&1; then
  echo "ERROR: commit $RECORDED is not in this repo (shallow or partial clone?)"
  exit 1
fi
echo "Verifying commit $RECORDED against $MANIFEST ..."

# 1. File hashes, from the recorded commit's tree.
CHECKED=0
while IFS= read -r line; do
  hash="${line%%  *}"
  path="${line#*  }"
  # Submodule paths are directories, covered by the submodule check (§3);
  # skip them if an older manifest listed them.
  if git ls-tree "$RECORDED" "$path" | grep -q '^160000 '; then continue; fi
  actual="$(git cat-file blob "$RECORDED:$path" 2>/dev/null | sha256sum | cut -d' ' -f1)"
  if [ "$actual" != "$hash" ]; then
    echo "MISMATCH: $path (manifest $hash, commit $actual)"
    FAILURES=$((FAILURES + 1))
  fi
  CHECKED=$((CHECKED + 1))
done < <(grep -E '^[0-9a-f]{64}  ' "$MANIFEST")
echo "Checked $CHECKED files from the manifest."

# 2. Submodule commits, from the recorded commit's gitlinks.
while IFS= read -r line; do
  # git submodule status line: "<hash> <path> (<describe>)" (leading space/+/-).
  sub_hash="$(echo "$line" | sed -E 's/^[-+ ]?([0-9a-f]{40}) .*/\1/')"
  sub_path="$(echo "$line" | awk '{print $2}')"
  [ -n "$sub_hash" ] || continue
  actual="$(git ls-tree "$RECORDED" "$sub_path" | awk '{print $3}')"
  if [ "$actual" != "$sub_hash" ]; then
    echo "MISMATCH: submodule $sub_path (manifest $sub_hash, commit ${actual:-none})"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK: submodule $sub_path ($sub_hash)"
  fi
done < <(sed -n '/^## 2. Submodules/,/^## 3. How to verify/p' "$MANIFEST" | grep -E '^[-+ ]?[0-9a-f]{40} ')

# 3. HEAD, informational only (see the header comment).
CURRENT="$(git rev-parse HEAD)"
if [ "$CURRENT" = "$RECORDED" ]; then
  echo "NOTE: HEAD is the recorded commit."
else
  echo "NOTE: HEAD ($CURRENT) differs from the recorded commit ($RECORDED) — expected when the manifest was committed separately."
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "MANIFEST VERIFIED: commit $RECORDED matches $MANIFEST"
  exit 0
else
  echo "MANIFEST FAILED: $FAILURES mismatch(es)"
  exit 1
fi
