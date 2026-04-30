// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../test/mocks/MockUSDC.sol";

contract DeployMockUSDC is Script {
    function run() external returns (MockUSDC mockUsdc) {
        vm.startBroadcast();
        mockUsdc = new MockUSDC();
        vm.stopBroadcast();
        console2.log("MockUSDC deployed at:", address(mockUsdc));
    }
}
