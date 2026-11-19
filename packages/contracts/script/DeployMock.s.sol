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
        require(block.chainid != 56, "DeployMock: mainnet forbidden, use official Agent ID");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        mock = new MockAgentId();
        vm.stopBroadcast();
        console.log("MockAgentId deployed at:", address(mock));
    }
}
