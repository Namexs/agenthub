// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Deploys MockAgentId for LOCAL (Anvil) or BSC TESTNET (chainId 97) only.
/// @dev NEVER run against BSC mainnet (chainId 56) — production uses the
/// official Agent ID contract 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
/// Usage (Phase 2):
///   CONFIRM_TESTNET_DEPLOY=true forge script script/DeployMock.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
/// Requires DEPLOYER_PRIVATE_KEY in the environment (see .env.example).
/// PHASE 9 (Workstream 2): testnet (97) requires the explicit opt-in
/// CONFIRM_TESTNET_DEPLOY=true, symmetric with DeployAgentHub (PH7-M05)
/// — before this, DeployMock was an unguarded broadcast path to testnet.
contract DeployMock is Script {
    /// @dev PHASE 9 (Workstream 2): testnet broadcast guard, symmetric
    /// with DeployAgentHub.TestnetDeployNotConfirmed.
    error TestnetDeployNotConfirmed();

    function run() external returns (MockAgentId mock) {
        // L4 fix (Phase 1 audit): allowlist, not denylist. The mock may only
        // ever be deployed to BSC testnet (97) or local Anvil (31337).
        require(block.chainid == 97 || block.chainid == 31337, "DeployMock: only BSC testnet (97) or Anvil (31337)");
        // PHASE 9 (Workstream 2): testnet requires an explicit opt-in —
        // no approval = no broadcast (local Anvil is exempt, like
        // DeployAgentHub).
        if (block.chainid == 97 && !vm.envOr("CONFIRM_TESTNET_DEPLOY", false)) {
            revert TestnetDeployNotConfirmed();
        }
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        mock = new MockAgentId();
        vm.stopBroadcast();
        console.log("MockAgentId deployed at:", address(mock));
    }
}
