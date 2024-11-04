// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {TestExt} from "forge-zksync-std/TestExt.sol";
import {GaslessPaymaster} from "../src/GaslessPaymaster.sol";

contract CounterScript is Script, TestExt {
    Counter public counter;
    GaslessPaymaster public paymaster;
    bytes private paymasterEncodedInput;

    function setUp() public {
        paymaster = new GaslessPaymaster();
        // Fund the paymaster with 0.005 ether using .call
        (bool success, ) = address(paymaster).call{value: 0.005 ether}("");
        require(success, "Funding paymaster failed");
    }

    function run() public {
        vm.startBroadcast();

        paymasterEncodedInput = abi.encodeWithSelector(
            bytes4(keccak256("general(bytes)")),
            bytes("")
        );
        vmExt.zkUsePaymaster(address(paymaster), paymasterEncodedInput);

        counter = new Counter();

        vm.stopBroadcast();
    }
}
