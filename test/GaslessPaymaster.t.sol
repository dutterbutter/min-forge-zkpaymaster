// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@matterlabs/era-contracts/interfaces/IPaymaster.sol";
import "@matterlabs/era-contracts/interfaces/IPaymasterFlow.sol";
import "@matterlabs/era-contracts/Constants.sol";
import {TestExt} from "forge-zksync-std/TestExt.sol";
import {GaslessPaymaster} from "../src/GaslessPaymaster.sol";
import {Greeter} from "../src/Greeter.sol";

contract GaslessPaymasterTest is Test, TestExt {
    GaslessPaymaster private paymaster;
    Greeter private greeter;
    address private owner;
    address private nonOwner;
    uint256 private ownerInitialBalance;
    bytes private paymasterEncodedInput;

    function setUp() public {
        owner = makeAddr("Owner");
        nonOwner = makeAddr("NonOwner");

        // Deploy the contracts
        vm.prank(owner);
        greeter = new Greeter("Hi");
        vm.prank(owner);
        paymaster = new GaslessPaymaster();

        // Fund the Paymaster and set initial balance
        vm.deal(address(paymaster), 3 ether);
        ownerInitialBalance = owner.balance;

        // Prepare encoded input for Paymaster's general call
        paymasterEncodedInput = abi.encodeWithSelector(
            bytes4(keccak256("general(bytes)")),
            bytes("")
        );

        assertEq(
            paymaster.owner(),
            owner,
            "Owner should be set to the deployer"
        );
    }

    function executeGreetingWithPaymaster(
        address user
    ) internal returns (uint256) {
        // Use the zkUsePaymaster cheatcode
        vmExt.zkUsePaymaster(address(paymaster), paymasterEncodedInput);

        // Execute the greeting function as the specified user
        vm.prank(user);
        greeter.setGreeting("Hola, mundo!");

        return owner.balance;
    }

    function testOwnerCanUpdateGreetingWithoutCost() public {
        uint256 newBalance = executeGreetingWithPaymaster(owner);

        // Assert greeting updated and owner balance unchanged
        assertEq(greeter.greet(), "Hola, mundo!");
        assertEq(
            newBalance,
            ownerInitialBalance,
            "Owner's balance should not change"
        );
    }

    function testOwnerCanWithdrawAllFunds() public {
        vm.prank(owner);
        paymaster.withdraw(payable(owner));

        // Verify Paymaster balance is zero after withdrawal
        assertEq(
            address(paymaster).balance,
            0,
            "Paymaster balance should be zero"
        );
    }

    function testFailNonOwnerCannotWithdrawFunds() public {
        // Non-owner attempts withdrawal, should fail
        vm.prank(nonOwner);
        paymaster.withdraw(payable(nonOwner));
    }
}
