// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafeSetup {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

/// @notice One-off experiment (Phase 1): on a BSC testnet FORK (no
/// broadcast), create one genuine Safe proxy per canonical factory and
/// print its runtime codehash. The codehashes become the constants in
/// SafeValidation.sol — a proxy whose codehash matches AND whose
/// masterCopy is a canonical singleton IS a genuine Safe proxy, because
/// the canonical proxy bytecode does nothing but delegatecall the
/// singleton in slot 0. Run:
///   forge script script/ProbeSafeProxy.s.sol --fork-url https://bsc-testnet-rpc.publicnode.com
contract ProbeSafeProxy is Script {
    address internal constant SINGLETON_141 = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant SINGLETON_130 = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address internal constant FACTORY_141 = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant FACTORY_130 = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;

    function run() external {
        address[] memory owners = new address[](2);
        owners[0] = address(0x1111111111111111111111111111111111111111);
        owners[1] = address(0x2222222222222222222222222222222222222222);
        bytes memory setupData = abi.encodeCall(
            ISafeSetup.setup, (owners, 2, address(0), bytes(""), address(0), address(0), 0, payable(address(0)))
        );

        address proxy141 = ISafeProxyFactory(FACTORY_141).createProxyWithNonce(SINGLETON_141, setupData, 20261119);
        console.log("proxy141:", proxy141);
        console.logBytes32(proxy141.codehash);
        console.log("proxy141 code:");
        console.logBytes(proxy141.code);

        address proxy130 = ISafeProxyFactory(FACTORY_130).createProxyWithNonce(SINGLETON_130, setupData, 20261119);
        console.log("proxy130:", proxy130);
        console.logBytes32(proxy130.codehash);
        console.log("proxy130 code:");
        console.logBytes(proxy130.code);
    }
}
