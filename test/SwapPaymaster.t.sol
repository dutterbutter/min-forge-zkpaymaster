// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TestExt} from "forge-zksync-std/TestExt.sol";
import {DynamicSwapPaymaster, IWETH} from "../src/SwapPaymaster.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Counter} from "../src/Counter.sol";

contract DynamicSwapPaymasterTest is Test, TestExt {
    DynamicSwapPaymaster private _paymaster;
    Counter private _counter;

    // Network and address variables from mainnet fork
    uint256 private _mainnetFork;
    address private _testUser;

    // External contract addresses
    address private constant WETH_ADDRESS =
        0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
    address private constant UNIVERSAL_ROUTER_ADDRESS =
        0x28731BCC616B5f51dD52CF2e4dF0E78dD1136C06;
    address private constant ZK_TOKEN_ADDRESS =
        0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
    address private constant ETH_TOKEN_ADDRESS =
        0x000000000000000000000000000000000000800A;
    address private constant USDC_ADDRESS =
        0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4;
    address private constant PERMIT2_ADDRESS =
        0x0000000000225e31D15943971F47aD3022F714Fa;
    address private constant QUOTER_ADDRESS =
        0x8Cb537fc92E26d8EBBb760E632c95484b6Ea3e28;

    function setUp() public {
        _mainnetFork = vm.createFork("https://mainnet.era.zksync.io");
        vm.selectFork(_mainnetFork);

        _paymaster = new DynamicSwapPaymaster(
            UNIVERSAL_ROUTER_ADDRESS,
            WETH_ADDRESS,
            USDC_ADDRESS,
            PERMIT2_ADDRESS,
            QUOTER_ADDRESS
        );

        _counter = new Counter();
        // TODO: check to see if I can use a different address
        _testUser = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);

        // Fund the test user with USDC
        deal(USDC_ADDRESS, _testUser, 12_560 * 10 ** 6);
    }

    // Test swapping tokens for ETH through the paymaster
    function testSwapUSDCForETHAndUsePaymaster() public {
        vm.startPrank(_testUser);

        uint256 initialGas = gasleft();
        _counter.setNumber(42);
        uint256 gasUsed = initialGas - gasleft();
        console.log("Gas used for setNumber call:", gasUsed);

        // TODO: figure out gas usage better
        uint256 customGasLimit = gasUsed + 10000;

        vm.stopPrank();
        vm.startPrank(_testUser);

        // Record initial balances
        uint256 initialUSDCBalance = IERC20(USDC_ADDRESS).balanceOf(_testUser);
        uint256 initialETHBalance = _testUser.balance;
        uint256 initialPaymasterETHBalance = address(_paymaster).balance;

        // Prepare paymaster data for the swap
        bytes memory paymasterInputData = abi.encodeWithSelector(
            bytes4(keccak256("approvalBased(address,uint256,bytes)")),
            USDC_ADDRESS,
            5_120 * 10 ** 6,
            bytes("")
        );

        vmExt.zkUsePaymaster(address(_paymaster), paymasterInputData);

        // TODO: figure out gas usage better
        uint256 gasPriceInGwei = uint256(0x2b275d0);
        uint256 gasPriceInWei = gasPriceInGwei * 1 gwei;
        vm.txGasPrice(gasPriceInWei);

        console.log("Gas price from curl (wei):", gasPriceInWei);
        console.log("Custom gas limit:", customGasLimit);

        // Interact with the counter contract
        _counter.setNumber{gas: customGasLimit}(42);

        assertEq(
            _counter.number(),
            42,
            "Counter value should be updated to 42"
        );

        // Record final balances
        uint256 finalUSDCBalance = IERC20(USDC_ADDRESS).balanceOf(_testUser);
        uint256 finalETHBalance = _testUser.balance;
        uint256 finalPaymasterETHBalance = address(_paymaster).balance;

        // Log balance changes
        console.log("Initial USDC balance:", initialUSDCBalance);
        console.log("Final USDC balance:", finalUSDCBalance);
        console.log("Initial ETH balance:", initialETHBalance);
        console.log("Final ETH balance:", finalETHBalance);
        console.log(
            "Initial paymaster ETH balance:",
            initialPaymasterETHBalance
        );
        console.log("Final paymaster ETH balance:", finalPaymasterETHBalance);

        // Validate balance changes
        require(
            initialUSDCBalance > finalUSDCBalance,
            "Test user's USDC balance should decrease after swap"
        );
        require(
            initialETHBalance == finalETHBalance,
            "Test user's ETH balance should remain unchanged"
        );

        vm.stopPrank();
    }
}
