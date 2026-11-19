#!/usr/bin/env bash
# Generate PACKAGE_MANIFEST.md for a given commit (default: HEAD).
# The manifest records the commit hash, submodule commits, and the sha256
# of every tracked file in that commit, so a reviewer can verify that a
# checkout (or a ZIP) matches the described commit exactly.
#
# Usage: ./scripts/generate-manifest.sh [commit]
# Output: PACKAGE_MANIFEST.md at the repo root.
#
# NOTE: the manifest describes the commit it was generated FROM. It is
# committed separately, AFTER that commit, and it excludes itself from its
# own file list (it did not exist in the described commit).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

COMMIT="${1:-HEAD}"
COMMIT="$(git rev-parse "$COMMIT")"
DATE="$(git show -s --format=%cI "$COMMIT")"
SUBJECT="$(git show -s --format=%s "$COMMIT")"

{
  echo "# AGENTHUB — Package Manifest"
  echo
  echo "This manifest describes one exact commit of the AGENTHUB repository:"
  echo "every tracked file and its sha256 hash, plus the submodule commits."
  echo "It lets a reviewer verify that their copy matches the described"
  echo "commit — something a ZIP alone cannot prove (see §3)."
  echo
  echo "## 1. Described commit"
  echo
  echo "- Commit: \`$COMMIT\`"
  echo "- Date: $DATE"
  echo "- Subject: $SUBJECT"
  echo
  echo "## 2. Submodules"
  echo
  echo "Submodule contents are NOT part of the file list below. Verify them"
  echo "separately with \`git submodule status\` after cloning with"
  echo "\`--recurse-submodules\` — the commits must match these:"
  echo
  echo '```'
  git submodule status "$COMMIT" 2>/dev/null || git submodule status
  echo '```'
  echo
  echo "## 3. How to verify"
  echo
  echo "The verification script checks the RECORDED COMMIT's tree (via git),"
  echo "not the working tree — so it works from any checkout that contains"
  echo "this manifest and the git history. HEAD does not need to equal the"
  echo "recorded commit."
  echo
  echo '```bash'
  echo "git clone --recurse-submodules <repo-url> agenthub"
  echo "cd agenthub"
  echo "./scripts/verify-manifest.sh"
  echo '```'
  echo
  echo "The script recomputes the sha256 of every file listed in §4 from the"
  echo "recorded commit (git cat-file) and compares it to this manifest, and"
  echo "checks the submodule gitlink commits against §2."
  echo
  echo "To also confirm your WORKING TREE matches the recorded commit, run"
  echo "\`git status\` (clean) and \`git rev-parse HEAD\` (should print the"
  echo "commit above, or a descendant of it)."
  echo
  echo "### Honest note about ZIPs and git archive"
  echo
  echo "\`git archive\` does NOT include submodules (lib/forge-std,"
  echo "lib/openzeppelin-contracts) or \`.git\` metadata. A ZIP produced by"
  echo "\`git archive\` therefore cannot, by itself, prove which commit it"
  echo "came from — the commit hash must be recorded out-of-band (as here)"
  echo "and the submodules fetched separately. To verify a ZIP: extract it,"
  echo "run \`sha256sum\` on its files, and compare against §4 (ignoring"
  echo "the manifest itself and any files the ZIP legitimately omits,"
  echo "such as submodule contents)."
  echo
  echo "## 4. Tracked files (sha256)"
  echo
  echo "Format: \`<sha256>  <path>\`, one file per line, sorted by path."
  echo "The manifest itself (PACKAGE_MANIFEST.md) is excluded: it is"
  echo "generated from the described commit and committed separately."
  echo
  echo '```'
  # ls-tree lists submodule gitlinks (mode 160000) too; skip them — they
  # are covered by §2, and git cat-file cannot hash a gitlink.
  git ls-tree -r "$COMMIT" | grep -v '^160000 ' | sed 's/.*\t//' | sort | while IFS= read -r f; do
    [ "$f" = "PACKAGE_MANIFEST.md" ] && continue
    printf '%s  %s\n' "$(git cat-file blob "$COMMIT:$f" | sha256sum | cut -d' ' -f1)" "$f"
  done
  echo '```'
} > PACKAGE_MANIFEST.md

echo "Wrote PACKAGE_MANIFEST.md for commit $COMMIT"
