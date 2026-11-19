// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockAgentId} from "../src/mocks/MockAgentId.sol";

/// @notice Deploys MockAgentId for LOCAL (Anvil) or BSC TESTNET (chainId 97) only.
/// @dev NEVER run against BSC mainnet (chainId 56) — production uses the
/// official Agent ID contract 0x60b9262456de011f7d15a54cdd8c48baaa8b022f.
/// Usage (Phase 2):
///   forge script script/DeployMock.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
/// Requires DEPLOYER_PRIVATE_KEY in the environment (see .env.example).
contract DeployMock is Script {
    function run() external returns (MockAgentId mock) {
        // L4 fix (Phase 1 audit): allowlist, not denylist. The mock may only
        // ever be deployed to BSC testnet (97) or local Anvil (31337).
        require(block.chainid == 97 || block.chainid == 31337, "DeployMock: only BSC testnet (97) or Anvil (31337)");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        mock = new MockAgentId();
        vm.stopBroadcast();
        console.log("MockAgentId deployed at:", address(mock));
    }
}
