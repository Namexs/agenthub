#!/usr/bin/env python3
"""AGENTHUB Phase 9 — Workstream 5 (audit preparation): bytecode audit of the
fresh forge build at the audit-commit HEAD.

Method (same as the Phase 8 scanner, agenthub-phase8-remediation/logs/
phase8-bytecode-audit.py): metadata CBOR is stripped before disassembly and
bytes inside PUSH immediates are never counted as opcodes, so the
Cancun-only opcode scan has no metadata false positives. Hashes reported
are keccak256 (via `cast keccak`, the canonical EVM hash) plus SHA-256
(for comparison with the Phase 8 published runtime hashes).

Usage: python3 bytecode-audit.py <contracts_out_dir>
Example: python3 bytecode-audit.py ../../../packages/contracts/out
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

CONTRACTS = ["AgentGate", "QuestManager", "Reputation", "Achievement"]
EIP170 = 24576
EIP3860 = 49152

# Cancun-only opcodes (EIP-1153 TLOAD 0x5c / TSTORE 0x5d, EIP-5656 MCOPY
# 0x5e, EIP-4844/7516 BLOBHASH 0x49 / BLOBBASEFEE 0x4a).
CANCUN_OPS = {0x5E: "MCOPY", 0x5D: "TSTORE", 0x5C: "TLOAD",
              0x4A: "BLOBBASEFEE", 0x49: "BLOBHASH"}

# Phase 8 published SHA-256 runtime hashes (final, solc 0.8.39) — the
# fresh build must reproduce these exactly.
PHASE8_SHA256_RUNTIME = {
    "AgentGate": "adb2e727d223a34f9a81ea9f886cee76d9020c939ef43f29ea81b974dffb32d8",
    "QuestManager": "c3120d24aebece3131bb77f78844616f61009e5b5cef04794d0066fcdb223e33",
    "Reputation": "2444f4eacd0b2dd28081021be417f9dea1f637ad98e2eb1d0202a3c9619c0258",
    "Achievement": "c4af7dedde69b1301c3ebcee2fb81c74f15083dc8b21c2b6ef70ff3d9fd75fe0",
}


def keccak256_hex(data: bytes) -> str:
    """Keccak-256 via `cast keccak` (no Python keccak lib on this VM)."""
    out = subprocess.run(
        ["cast", "keccak", "0x" + data.hex()],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def strip_metadata(code: bytes) -> bytes:
    """Remove the trailing CBOR metadata: last 2 bytes are its length."""
    if len(code) < 2:
        return code
    meta_len = int.from_bytes(code[-2:], "big")
    if 0 < meta_len < len(code):
        return code[: -2 - meta_len]
    return code


def disassemble(code: bytes):
    """Yield (pc, opcode), skipping PUSH immediates."""
    pc = 0
    n = len(code)
    while pc < n:
        op = code[pc]
        yield pc, op
        if 0x60 <= op <= 0x7F:  # PUSH1..PUSH32
            pc += 1 + (op - 0x5F)
        else:
            pc += 1


def audit(out_dir: Path) -> dict:
    results = {}
    for name in CONTRACTS:
        artifact = json.loads((out_dir / f"{name}.sol" / f"{name}.json").read_text())
        creation = bytes.fromhex(artifact["bytecode"]["object"][2:])
        deployed = bytes.fromhex(artifact["deployedBytecode"]["object"][2:])
        code_section = strip_metadata(deployed)
        cancun = []
        for pc, op in disassemble(code_section):
            if op in CANCUN_OPS:
                cancun.append(f"{CANCUN_OPS[op]} @ PC {pc} (0x{pc:x})")
        sha256_runtime = hashlib.sha256(deployed).hexdigest()
        results[name] = {
            "compiler": artifact["metadata"]["compiler"]["version"],
            "creation_bytes": len(creation),
            "deployed_bytes": len(deployed),
            "creation_pct_eip3860": round(100 * len(creation) / EIP3860, 2),
            "deployed_pct_eip170": round(100 * len(deployed) / EIP170, 2),
            "keccak256_creation": keccak256_hex(creation),
            "keccak256_deployed": keccak256_hex(deployed),
            "sha256_deployed": sha256_runtime,
            "sha256_matches_phase8": sha256_runtime == PHASE8_SHA256_RUNTIME[name],
            "metadata_cbor_bytes": len(deployed) - len(code_section),
            "cancun_opcodes": cancun,
            "link_references": artifact["bytecode"].get("linkReferences", {}),
        }
    return results


def main() -> int:
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else
                   "../../packages/contracts/out")
    results = audit(out_dir)
    all_match = True
    for name, r in results.items():
        print(f"-- {name} --")
        print(f"  compiler            : {r['compiler']}")
        print(f"  creation size       : {r['creation_bytes']} byte "
              f"({r['creation_pct_eip3860']}% EIP-3860)")
        print(f"  deployed size       : {r['deployed_bytes']} byte "
              f"({r['deployed_pct_eip170']}% EIP-170)")
        print(f"  keccak256 creation  : {r['keccak256_creation']}")
        print(f"  keccak256 deployed  : {r['keccak256_deployed']}")
        print(f"  sha256 deployed     : {r['sha256_deployed']}")
        print(f"  sha256 == Phase 8   : "
              f"{'MATCH' if r['sha256_matches_phase8'] else 'MISMATCH !!!'}")
        print(f"  metadata CBOR       : {r['metadata_cbor_bytes']} byte")
        print(f"  Cancun-only opcodes : "
              f"{'; '.join(r['cancun_opcodes']) if r['cancun_opcodes'] else '0'}")
        print(f"  linkReferences      : "
              f"{r['link_references'] if r['link_references'] else 'empty'}")
        all_match = all_match and r["sha256_matches_phase8"]
    print(f"\nALL SHA-256 MATCH PHASE 8: {all_match}")
    return 0 if all_match else 1


if __name__ == "__main__":
    raise SystemExit(main())
