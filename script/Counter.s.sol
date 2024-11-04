// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {TestExt} from "forge-zksync-std/TestExt.sol";

contract CounterScript is Script, TestExt {
    Counter public counter;
    // Paymaster on ZKsync Sepolia
    address public paymaster = 0x5f26bf2FF05cd06484cf7C68ad360D336704e46C;
    bytes private paymasterEncodedInput;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        console.log("Using Paymaster at address:", paymaster);

        // Ensure the paymaster is funded
        uint256 paymasterBalance = address(paymaster).balance;
        console.log("Paymaster balance after funding:", paymasterBalance);
        require(
            paymasterBalance > 0.005 ether,
            "Paymaster balance is not greater than 0.005 ether"
        );

        // Prepare encoded input for using the Paymaster
        paymasterEncodedInput = abi.encodeWithSelector(
            bytes4(keccak256("general(bytes)")),
            bytes("")
        );
        // Use the zkUsePaymaster cheatcode for next transaction
        vmExt.zkUsePaymaster(paymaster, paymasterEncodedInput);
        // Deploy the Counter contract using the Paymaster
        counter = new Counter();

        console.log("Counter address:", address(counter));

        vmExt.zkUsePaymaster(paymaster, paymasterEncodedInput);
        counter.setNumber(42);

        console.log("Deployer balance:", address(this).balance);

        vm.stopBroadcast();
    }

    receive() external payable {}
}
