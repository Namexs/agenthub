// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @notice Minimal Safe (v1.3.0 / v1.4.1) interface for executing a
/// transaction: nonce + owners for pre-flight checks, getTransactionHash
/// for the EIP-712 SafeTx hash, execTransaction for submission.
/// @dev getTransactionHash/execTransaction take the Operation as a
/// uint8 in the ABI (Safe's Enum.Operation) — this script only ever
/// uses Operation.Call (0).
interface ISafeExec {
    function nonce() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}

/// @title SafeExec
/// @notice Generic 2-of-3 Safe (v1.4.1) execTransaction runner for the
/// AGENTHUB testnet smoke test. The Safe web app does not list BSC
/// Testnet, so Safe calls (mint test Agent IDs, schedule timelock
/// operations) are executed from the operator's own machine with two
/// owner keys instead.
/// @dev Flow: read the Safe nonce live -> compute the SafeTx hash via
/// getTransactionHash -> sign with BOTH owner keys (vm.sign, off-chain
/// in the script process — the keys never leave the operator's machine)
/// -> sort the two signatures by signer address ascending (Safe
/// requires ascending order, GS026 otherwise) -> broadcast
/// execTransaction from signer 1. The submitter pays gas; the Safe
/// itself pays nothing (gasPrice 0, no refund).
/// @dev Safety: the script reverts BEFORE broadcasting if either
/// derived signer is not a Safe owner, or if both keys derive the
/// same signer — a doomed transaction is never submitted. Keys are
/// never logged.
/// @dev Env interface:
///   SAFE_ADDRESS         the Safe proxy address
///   SAFE_TO              call target (contract to call)
///   SAFE_DATA            hex calldata for the call (0x-prefixed)
///   SAFE_VALUE           wei to send with the call (optional, default 0)
///   DEPLOYER_PRIVATE_KEY signer 1 AND tx submitter (must be a Safe owner)
///   SAFE_OWNER_KEY_2     signer 2 (another Safe owner)
/// @dev Usage:
///   SAFE_ADDRESS=<safe> SAFE_TO=<target> SAFE_DATA=<0x..> \
///   DEPLOYER_PRIVATE_KEY=<key1> SAFE_OWNER_KEY_2=<key2> \
///   forge script script/SafeExec.s.sol --rpc-url <url> --broadcast
contract SafeExec is Script {
    error ZeroAddress(string param);
    error NoCodeAtSafe(address safe);
    error SignerNotOwner(address signer);
    error DuplicateSigner(address signer);
    error ExecFailed(bytes32 txHash, uint256 nonce);

    /// @notice Execute one Safe call with two owner signatures.
    function run() external {
        address safeAddr = vm.envAddress("SAFE_ADDRESS");
        address to = vm.envAddress("SAFE_TO");
        bytes memory data = vm.envBytes("SAFE_DATA");
        uint256 value = vm.envOr("SAFE_VALUE", uint256(0));
        uint256 key1 = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 key2 = vm.envUint("SAFE_OWNER_KEY_2");

        if (safeAddr == address(0)) revert ZeroAddress("SAFE_ADDRESS");
        if (to == address(0)) revert ZeroAddress("SAFE_TO");
        if (safeAddr.code.length == 0) revert NoCodeAtSafe(safeAddr);

        address signer1 = vm.addr(key1);
        address signer2 = vm.addr(key2);
        if (signer1 == signer2) revert DuplicateSigner(signer1);

        ISafeExec safe = ISafeExec(safeAddr);
        address[] memory owners = safe.getOwners();
        if (!_isOwner(owners, signer1)) revert SignerNotOwner(signer1);
        if (!_isOwner(owners, signer2)) revert SignerNotOwner(signer2);

        uint256 nonce = safe.nonce();
        bytes32 txHash = safe.getTransactionHash(to, value, data, 0, 0, 0, 0, address(0), address(0), nonce);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(key1, txHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(key2, txHash);
        bytes memory sig1 = abi.encodePacked(r1, s1, v1);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2);
        // Safe verifies signatures in ascending signer order.
        bytes memory signatures = signer1 < signer2 ? abi.encodePacked(sig1, sig2) : abi.encodePacked(sig2, sig1);

        console.log("SafeExec: safe");
        console.log(safeAddr);
        console.log(string.concat("SafeExec: nonce ", vm.toString(nonce)));
        console.log("SafeExec: txHash");
        console.logBytes32(txHash);
        console.log("SafeExec: signer 1");
        console.log(signer1);
        console.log("SafeExec: signer 2");
        console.log(signer2);

        vm.startBroadcast(key1);
        bool success = safe.execTransaction(to, value, data, 0, 0, 0, 0, address(0), payable(address(0)), signatures);
        vm.stopBroadcast();
        if (!success) revert ExecFailed(txHash, nonce);

        console.log("SafeExec: EXECUTED");
        console.log(string.concat("SafeExec: nonce used ", vm.toString(nonce)));
    }

    function _isOwner(address[] memory owners, address signer) internal pure returns (bool) {
        for (uint256 i = 0; i < owners.length; ++i) {
            if (owners[i] == signer) return true;
        }
        return false;
    }
}
