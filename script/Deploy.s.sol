// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LoafEscrow.sol";

contract Deploy is Script {
    function run() external returns (LoafEscrow escrow) {
        address usdc = vm.envAddress("USDC_ADDRESS");
        vm.startBroadcast();
        escrow = new LoafEscrow(usdc);
        vm.stopBroadcast();
        console2.log("LoafEscrow deployed at:", address(escrow));
    }
}
