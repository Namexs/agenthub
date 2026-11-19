#!/usr/bin/env bash
# Verify the current checkout against PACKAGE_MANIFEST.md.
# - Checks HEAD matches the commit recorded in the manifest.
# - Recomputes the sha256 of every file listed in the manifest and
#   compares it (files missing from the checkout are reported).
# - Checks submodule commits against the manifest.
# Exit 0 = all checks pass; exit 1 = any mismatch.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MANIFEST="PACKAGE_MANIFEST.md"
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST not found"; exit 1; }

FAILURES=0

# 1. HEAD matches the recorded commit.
RECORDED="$(grep -m1 '^- Commit: `' "$MANIFEST" | sed -E 's/^- Commit: `([0-9a-f]+)`.*/\1/')"
CURRENT="$(git rev-parse HEAD)"
if [ "$RECORDED" != "$CURRENT" ]; then
  echo "MISMATCH: HEAD is $CURRENT, manifest describes $RECORDED"
  FAILURES=$((FAILURES + 1))
else
  echo "OK: HEAD matches the manifest commit ($CURRENT)"
fi

# 2. File hashes. The manifest lists files as "<sha256>  <path>" lines.
CHECKED=0
while IFS= read -r line; do
  hash="${line%%  *}"
  path="${line#*  }"
  [ -f "$path" ] || { echo "MISSING: $path"; FAILURES=$((FAILURES + 1)); continue; }
  actual="$(sha256sum "$path" | cut -d' ' -f1)"
  if [ "$actual" != "$hash" ]; then
    echo "MISMATCH: $path (expected $hash, got $actual)"
    FAILURES=$((FAILURES + 1))
  fi
  CHECKED=$((CHECKED + 1))
done < <(grep -E '^[0-9a-f]{64}  ' "$MANIFEST")
echo "Checked $CHECKED files from the manifest."

# 3. Submodule commits.
while IFS= read -r line; do
  # git submodule status line: "<hash> <path> (<describe>)" (leading space/+/-
  # indicates checkout state; strip it).
  sub_hash="$(echo "$line" | sed -E 's/^[-+ ]?([0-9a-f]{40}) .*/\1/')"
  sub_path="$(echo "$line" | awk '{print $2}')"
  [ -n "$sub_hash" ] || continue
  actual="$(git -C "$sub_path" rev-parse HEAD 2>/dev/null || echo MISSING)"
  if [ "$actual" != "$sub_hash" ]; then
    echo "MISMATCH: submodule $sub_path (expected $sub_hash, got $actual)"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK: submodule $sub_path ($sub_hash)"
  fi
done < <(sed -n '/^## 2. Submodules/,/^## 3. How to verify/p' "$MANIFEST" | grep -E '^[-+ ]?[0-9a-f]{40} ')

if [ "$FAILURES" -eq 0 ]; then
  echo "MANIFEST VERIFIED: checkout matches $MANIFEST"
  exit 0
else
  echo "MANIFEST FAILED: $FAILURES mismatch(es)"
  exit 1
fi
