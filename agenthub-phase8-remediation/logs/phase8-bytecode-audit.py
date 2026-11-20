#!/usr/bin/env python3
"""AGENTHUB Phase 8 (Worker E) — bytecode audit: runtime + creation sizes,
EIP-170/EIP-3860 headroom, metadata-aware Cancun-only opcode scan, and
solc-vs-code decomposition of the size delta.

Adapted from Worker D's phase8-bytecode-audit.py (same disassembly +
metadata-strip method; artifact path updated to forge 1.9's out/src/
layout, creation bytecode + published-hash verification added).

Usage: python3 phase8-bytecode-audit.py <final_out_dir> <baseline_out_dir>
"""
import json, sys, hashlib
from pathlib import Path
from collections import Counter

CONTRACTS = ["AgentGate", "QuestManager", "Reputation", "Achievement"]
EIP170 = 24576
EIP3860 = 49152

# Cancun-only opcodes — canonical numbers (verified vs EIP + cast 1.9.0):
# EIP-1153: TLOAD 0x5c, TSTORE 0x5d; EIP-5656: MCOPY 0x5e;
# EIP-4844/7516: BLOBHASH 0x49, BLOBBASEFEE 0x4a.
CANCUN_OPS = {0x5e: "MCOPY", 0x5d: "TSTORE", 0x5c: "TLOAD",
              0x4a: "BLOBBASEFEE", 0x49: "BLOBHASH"}

# Worker D (solc-evaluation.md §6.3): SHA-256 runtime baseline 0.8.24,
# HEAD 5723ff3 — used to verify the rebuilt baseline reproduces it.
PUBLISHED_BASELINE_SHA = {
    "AgentGate": "e990c4fc2653f624a5638c593ce1d263158229e9abbdb1ddb5f2d1670b3d82a6",
    "QuestManager": "ce2e7168128e93c28b1a86b33cd06a0e89cd87f2004b43bad888703f2a3501a3",
    "Reputation": "f75326eb3f94b187f0b93be4099465bdd2df37ec4bd948b308e94fde1e3a4b4d",
    "Achievement": "1beab180e8cc2801a2b868150b39e974a16fa08219ae06fb3e8973dd951cba0f",
}
# Worker D (solc-evaluation.md §6.1-6.2): OLD code (HEAD 5723ff3) built
# with solc 0.8.39 — the intermediate point that separates the solc
# effect from the Phase 8 code effect.
WORKER_D_0839_RUNTIME = {"AgentGate": 1058, "QuestManager": 11684,
                         "Reputation": 2255, "Achievement": 5980}
WORKER_D_0839_CREATION = {"AgentGate": 1457, "QuestManager": 13404,
                          "Reputation": 2584, "Achievement": 7093}

def disassemble(code: bytes):
    pc = 0
    n = len(code)
    while pc < n:
        op = code[pc]
        yield pc, op
        if 0x60 <= op <= 0x7f:  # PUSH1..PUSH32
            pc += 1 + (op - 0x5f)
        else:
            pc += 1

def strip_metadata(code: bytes):
    if len(code) < 2:
        return code, None
    mlen = int.from_bytes(code[-2:], "big")
    if 0 < mlen < len(code) - 2:
        meta = code[len(code) - 2 - mlen: len(code) - 2]
        if meta and meta[0] in (0xa1, 0xa2, 0xa3, 0xa4):
            return code[:len(code) - 2 - mlen], meta
    return code, None

def load_artifact(out_dir: Path, name: str):
    for p in (out_dir / "src" / f"{name}.sol" / f"{name}.json",
              out_dir / f"{name}.sol" / f"{name}.json"):
        if p.exists():
            return json.loads(p.read_text()), p
    raise FileNotFoundError(f"no artifact for {name} under {out_dir}")

def analyse(out_dir: Path, label: str, verify_hashes: bool = False):
    print(f"\n===== {label} ({out_dir}) =====")
    results = {}
    for name in CONTRACTS:
        art, path = load_artifact(out_dir, name)
        raw = bytes.fromhex(art["deployedBytecode"]["object"][2:])
        creation = bytes.fromhex(art["bytecode"]["object"][2:])
        code, meta = strip_metadata(raw)
        ops = list(disassemble(code))
        hist = Counter(op for _, op in ops)
        cancun = {CANCUN_OPS[op]: [pc for pc, o in ops if o == op]
                  for op in CANCUN_OPS if hist.get(op, 0)}
        total_cancun = sum(hist.get(op, 0) for op in CANCUN_OPS)
        raw_grep = {CANCUN_OPS[op]: raw.count(bytes([op])) for op in CANCUN_OPS}
        h = hashlib.sha256(raw).hexdigest()
        size = len(raw)
        csize = len(creation)
        results[name] = dict(raw=raw, code=code, meta=meta, hist=hist,
                             cancun=cancun, total_cancun=total_cancun,
                             raw_grep=raw_grep, sha256=h, size=size,
                             creation_size=csize,
                             compiler=art["metadata"]["compiler"]["version"])
        print(f"\n-- {name} -- (artifact: {path})")
        print(f"  compiler          : {art['metadata']['compiler']['version']}")
        print(f"  runtime size      : {size} byte ({100.0*size/EIP170:.2f}% EIP-170; headroom {EIP170-size})")
        print(f"  creation size     : {csize} byte ({100.0*csize/EIP3860:.2f}% EIP-3860; headroom {EIP3860-csize})")
        print(f"  sha256 runtime    : {h}")
        if verify_hashes:
            ok = h == PUBLISHED_BASELINE_SHA[name]
            print(f"  vs published Phase 7 hash: {'COCOK' if ok else 'TIDAK COCOK — ' + PUBLISHED_BASELINE_SHA[name]}")
        print(f"  metadata CBOR     : {'ada, %d byte' % len(meta) if meta else 'TIDAK TERDETEKSI'}"
              + (f", hex: {meta.hex()}" if meta else ""))
        print(f"  code section ends : offset {len(code)} (runtime {len(raw)})")
        print(f"  opcode Cancun-only (disassembly, code section saja): total {total_cancun}")
        for opname, pcs in cancun.items():
            print(f"    {opname}: {len(pcs)}x di PC {[f'{p} (0x{p:x})' for p in pcs]}")
        print(f"  raw-hex grep (SEMUA byte incl. PUSH/metadata — rawan false positive): "
              + ", ".join(f"{k}={v}" for k, v in raw_grep.items()))
        print(f"  total instruksi   : {len(ops)}")
        lr = art["deployedBytecode"].get("linkReferences", {})
        print(f"  linkReferences    : {lr if lr else 'kosong (tidak ada library eksternal)'}")
    return results

def main():
    final = Path(sys.argv[1]); base = Path(sys.argv[2])
    r_fin = analyse(final, "FINAL Phase 8 — kode Phase 8 @ solc 0.8.39")
    r_bas = analyse(base, "BASELINE — HEAD 5723ff3 @ solc 0.8.24", verify_hashes=True)

    print("\n===== PERBANDINGAN FINAL vs BASELINE + DEKOMPOSISI =====")
    print("(efek solc = Worker D old-code@0.8.39 − baseline 0.8.24;")
    print(" efek kode = final − Worker D old-code@0.8.39)")
    for name in CONTRACTS:
        f, b = r_fin[name], r_bas[name]
        d_rt = f["size"] - b["size"]
        d_cr = f["creation_size"] - b["creation_size"]
        solc_rt = WORKER_D_0839_RUNTIME[name] - b["size"]
        code_rt = f["size"] - WORKER_D_0839_RUNTIME[name]
        solc_cr = WORKER_D_0839_CREATION[name] - b["creation_size"]
        code_cr = f["creation_size"] - WORKER_D_0839_CREATION[name]
        print(f"\n-- {name} --")
        print(f"  runtime : baseline {b['size']} -> WorkerD-0.8.39 {WORKER_D_0839_RUNTIME[name]} -> final {f['size']}")
        print(f"    efek solc {solc_rt:+d} byte; efek kode {code_rt:+d} byte; total {d_rt:+d} ({100.0*d_rt/b['size']:+.2f}%)")
        print(f"    % EIP-170: {100.0*b['size']/EIP170:.2f}% -> {100.0*f['size']/EIP170:.2f}%")
        print(f"  creation: baseline {b['creation_size']} -> WorkerD-0.8.39 {WORKER_D_0839_CREATION[name]} -> final {f['creation_size']}")
        print(f"    efek solc {solc_cr:+d} byte; efek kode {code_cr:+d} byte; total {d_cr:+d} ({100.0*d_cr/b['creation_size']:+.2f}%)")
        print(f"    % EIP-3860: {100.0*b['creation_size']/EIP3860:.2f}% -> {100.0*f['creation_size']/EIP3860:.2f}%")
        print(f"  sha256 baseline: {b['sha256']}")
        print(f"  sha256 final   : {f['sha256']}")
        print(f"  opcode Cancun-only: baseline {b['total_cancun']} -> final {f['total_cancun']}")
        print(f"  total instruksi   : baseline {sum(b['hist'].values())} -> final {sum(f['hist'].values())}")
        print(f"  metadata baseline : {b['meta'].hex() if b['meta'] else 'none'}")
        print(f"  metadata final    : {f['meta'].hex() if f['meta'] else 'none'}")

if __name__ == "__main__":
    main()
