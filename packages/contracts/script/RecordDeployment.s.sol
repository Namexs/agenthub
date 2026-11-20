// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @title RecordDeployment
/// @notice Post-broadcast enrichment for the deployment artifact
/// (PH7-L18). DeployAgentHub.run() writes deployments/<chainId>.json
/// with addresses, chainId and block number — but NOT tx hashes:
/// forge sends the broadcast transactions only after the deploy
/// script returns, so the script itself can never know them. This
/// script closes the gap: it reads forge's broadcast artifact
/// (broadcast/DeployAgentHub.s.sol/<chainId>/run-latest.json),
/// matches each contract-creation receipt by its contractAddress
/// (top-level `receipts` array — forge 1.9 does NOT embed receipts
/// in the per-tx objects), and rewrites the deployment artifact with
/// the deployment transaction hash per contract. It also corrects
/// blockNumber to the block the deployment txs actually landed in:
/// the script only knows the pre-broadcast simulation block.
/// @dev Matching rules (deliberately strict):
/// - Only RECEIPTED transactions count. A dry-run broadcast file
///   has an empty `receipts` array and predicted hashes, which must
///   never be recorded as real deployment hashes: a dry-run file
///   leaves every tx hash empty (with a warning) instead of failing.
/// - A receipt matches a contract only when its contractAddress
///   equals the artifact's address for that contract. Non-create
///   receipts have a null contractAddress and never match; receipts
///   that fail to parse are skipped, never fatal.
/// - Existing tx hashes in the artifact are PRESERVED when no
///   matching tx is found, so re-running is idempotent and never
///   clobbers a previously recorded hash.
/// - This script NEVER broadcasts and NEVER reads keys: pure file
///   I/O. Run it after `forge script ... --broadcast` completes:
///     CHAIN_ID=97 forge script script/RecordDeployment.s.sol
/// @dev No RPC is needed, and block.chainid is NOT used (an
/// in-memory run would report 31337); the chain comes from CHAIN_ID.
contract RecordDeployment is Script {
    error DeploymentArtifactNotFound(string path);
    error BroadcastArtifactNotFound(string path);

    /// @notice Env-driven entry point for `forge script`.
    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");
        string memory deploymentPath = string.concat("deployments/", vm.toString(chainId), ".json");
        string memory broadcastPath =
            string.concat("broadcast/DeployAgentHub.s.sol/", vm.toString(chainId), "/run-latest.json");
        record(deploymentPath, broadcastPath);
    }

    /// @notice Enriches the artifact at `deploymentPath` with tx
    /// hashes from the broadcast file at `broadcastPath`, in place.
    /// @return path The deployment artifact path that was rewritten.
    function record(string memory deploymentPath, string memory broadcastPath) public returns (string memory path) {
        if (!vm.exists(deploymentPath)) revert DeploymentArtifactNotFound(deploymentPath);
        if (!vm.exists(broadcastPath)) revert BroadcastArtifactNotFound(broadcastPath);

        string memory deploymentJson = vm.readFile(deploymentPath);
        string memory broadcastJson = vm.readFile(broadcastPath);

        string[6] memory names = ["mockAgentId", "agentGate", "timelock", "reputation", "achievement", "questManager"];
        address[6] memory addrs;
        string[6] memory hashes;
        uint256 matched;
        uint256 minedBlock; // max receipt block across matched txs
        for (uint256 i = 0; i < 6; i++) {
            string memory addrKey = string.concat(".", names[i]);
            string memory hashKey = string.concat(".", names[i], "TxHash");
            addrs[i] = vm.parseJsonAddress(deploymentJson, addrKey);
            // A broadcast match wins; otherwise the artifact's existing
            // hash is preserved (idempotent re-runs, partial files).
            (string memory found, uint256 foundBlock) = _findTx(broadcastJson, addrs[i]);
            if (bytes(found).length != 0) {
                hashes[i] = found;
                matched++;
                if (foundBlock > minedBlock) minedBlock = foundBlock;
            } else {
                hashes[i] = vm.parseJsonString(deploymentJson, hashKey);
            }
        }
        // The artifact's blockNumber is the block the deploy script
        // SIMULATED at (pre-broadcast); the receipts say where the
        // txs actually landed — prefer the latter when known.
        uint256 blockNumber = vm.parseJsonUint(deploymentJson, ".blockNumber");
        if (minedBlock != 0) blockNumber = minedBlock;

        // Rewrite the artifact with the same flat 16-field schema,
        // preserving the recorded metadata verbatim.
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", vm.parseJsonUint(deploymentJson, ".chainId"));
        vm.serializeUint(obj, "blockNumber", blockNumber);
        vm.serializeUint(obj, "timestamp", vm.parseJsonUint(deploymentJson, ".timestamp"));
        vm.serializeAddress(obj, "deployer", vm.parseJsonAddress(deploymentJson, ".deployer"));
        for (uint256 i = 0; i < 6; i++) {
            vm.serializeAddress(obj, names[i], addrs[i]);
        }
        for (uint256 i = 0; i < 5; i++) {
            vm.serializeString(obj, string.concat(names[i], "TxHash"), hashes[i]);
        }
        string memory json = vm.serializeString(obj, string.concat(names[5], "TxHash"), hashes[5]);
        vm.writeJson(json, deploymentPath);

        // NOTE: single-string log — the multi-arg console.log
        // overloads do not render in `forge script` output (verified
        // on forge 1.9.0: (string, ...) lines silently vanish).
        console.log(
            string.concat(
                "RecordDeployment: ", deploymentPath, " enriched with ", vm.toString(matched), "/6 deployment tx hashes"
            )
        );
        if (matched == 0) {
            console.log(
                "RecordDeployment: WARNING - no CREATE receipt matched; is this a dry-run broadcast file (empty receipts array)?"
            );
        }
        return deploymentPath;
    }

    /// @notice Finds the deployment tx (hash + mined block) for
    /// `target` in the broadcast file: the receipt whose
    /// contractAddress equals `target`. Returns ("", 0) when there is
    /// no such receipt (dry-run file with an empty `receipts` array,
    /// non-create receipts, unparseable entries — all skipped, never
    /// fatal). The block is 0 when the receipt carries no parseable
    /// block number; the hash still counts.
    /// @dev Receipts live in the TOP-LEVEL `receipts` array (forge
    /// 1.9): the per-tx `receipt` field is always null. A dry-run
    /// file has `"receipts": []`, so the scan ends at index 0.
    function _findTx(string memory broadcastJson, address target)
        internal
        returns (string memory hash, uint256 blockNumber)
    {
        if (target == address(0)) return ("", 0);
        // NOTE: foundry's JSONPath has no array-length query here
        // (parseJsonKeys requires an object; ".receipts.length" is
        // unsupported), so the scan walks indices until the first
        // entry without a transactionHash — every forge receipt
        // carries one, so that is the end of the array.
        for (uint256 i = 0;; i++) {
            string memory base = string.concat(".receipts[", vm.toString(i), "]");
            try vm.parseJsonString(broadcastJson, string.concat(base, ".transactionHash")) returns (string memory h) {
                // parseJsonAddress reverts on a null contractAddress
                // (non-create receipt) — try/catch skips those; only
                // a CREATE receipt can match.
                try vm.parseJsonAddress(broadcastJson, string.concat(base, ".contractAddress")) returns (
                    address created
                ) {
                    if (created == target) {
                        hash = h;
                        try vm.parseJsonString(broadcastJson, string.concat(base, ".blockNumber")) returns (
                            string memory blockHex
                        ) {
                            blockNumber = _hexToUint(blockHex);
                        } catch {
                            // No (parseable) block number — the hash
                            // still counts; the block stays 0.
                        }
                        return (hash, blockNumber);
                    }
                } catch {
                    // Not a CREATE receipt — skip.
                }
            } catch {
                // No receipt at this index — end of the array.
                return ("", 0);
            }
        }
    }

    /// @dev Parses a "0x..." hex string into a uint (receipt
    /// blockNumbers are hex strings in forge broadcast files).
    /// Returns 0 on any malformed input — the block number is
    /// best-effort metadata, never a reason to fail the record.
    function _hexToUint(string memory s) internal pure returns (uint256 n) {
        bytes memory b = bytes(s);
        uint256 start = 0;
        if (b.length >= 2 && b[0] == "0" && (b[1] == "x" || b[1] == "X")) start = 2;
        if (b.length == start) return 0;
        for (uint256 i = start; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            uint256 digit;
            if (c >= 48 && c <= 57) digit = c - 48;
            else if (c >= 97 && c <= 102) digit = c - 87;
            else if (c >= 65 && c <= 70) digit = c - 55;
            else return 0;
            n = n * 16 + digit;
        }
    }
}
