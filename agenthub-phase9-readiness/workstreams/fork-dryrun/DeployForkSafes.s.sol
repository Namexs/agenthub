// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @notice FORK DRY-RUN ONLY (AGENTHUB Phase 9, Workstream 4). Deploys two
/// genuine Safe v1.4.1 proxies on a LOCAL anvil fork of BSC testnet
/// (chain 97) via the canonical SafeProxyFactory, so DeployAgentHub's
/// SafeValidation (canonical singleton + proxy codehash + threshold >= 2)
/// passes exactly as it would on live testnet. Owners are the PUBLIC
/// anvil test accounts 1/2/3; threshold 2-of-3. NEVER run against a real
/// chain: the owners are public test keys holding no real funds.
/// @dev Run from packages/contracts/:
///   forge script <this file> --rpc-url http://127.0.0.1:8545 \
///     --broadcast --private-key <anvil key 0>
interface ISafeProxyFactory {
    function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

contract DeployForkSafes is Script {
    address internal constant SINGLETON_V141 = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant FACTORY_V141 = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;

    function run() external {
        require(block.chainid == 97, "DeployForkSafes: chain-97 fork only");
        address[] memory owners = new address[](3);
        owners[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // anvil account 1
        owners[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // anvil account 2
        owners[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // anvil account 3
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (owners, uint256(2), address(0), bytes(""), address(0), address(0), uint256(0), payable(address(0)))
        );
        vm.startBroadcast();
        address adminSafe =
            ISafeProxyFactory(FACTORY_V141).createProxyWithNonce(SINGLETON_V141, initializer, 1);
        address creatorSafe =
            ISafeProxyFactory(FACTORY_V141).createProxyWithNonce(SINGLETON_V141, initializer, 2);
        vm.stopBroadcast();
        console.log("ADMIN_SAFE:", adminSafe);
        console.log("CREATOR_SAFE:", creatorSafe);
    }
}
