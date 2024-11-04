// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "era-universal-router/contracts/interfaces/IUniversalRouter.sol";
import "lib/Permit2/src/interfaces/IPermit2.sol";
import "lib/era-uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract UniversalRouterTest is Test {
    // Universal Router address on zkSync
    address private constant UNIVERSAL_ROUTER_ADDRESS =
        0x28731BCC616B5f51dD52CF2e4dF0E78dD1136C06;
    address private constant PERMIT2_ADDRESS =
        0x0000000000225e31D15943971F47aD3022F714Fa;

    // Address of WETH and USDC on zkSync
    address private constant WETH_ADDRESS =
        0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
    address private constant USDC_ADDRESS =
        0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4;

    IUniversalRouter private universalRouter;
    IERC20 private weth;
    IERC20 private usdc;
    IPermit2 private permit2;

    function setUp() public {
        universalRouter = IUniversalRouter(UNIVERSAL_ROUTER_ADDRESS);
        permit2 = IPermit2(PERMIT2_ADDRESS);
        weth = IERC20(WETH_ADDRESS);
        usdc = IERC20(USDC_ADDRESS);

        // Allocate WETH to the contract for testing
        deal(WETH_ADDRESS, address(this), 1 ether);

        // Approve the Permit2 contract for WETH
        weth.approve(PERMIT2_ADDRESS, type(uint256).max);
        console.log("WETH approved for Permit2");
        // Use Permit2 to approve the Universal Router to spend WETH
        permit2.approve(
            WETH_ADDRESS,
            UNIVERSAL_ROUTER_ADDRESS,
            type(uint160).max,
            uint48(block.timestamp + 15 minutes)
        );
        console.log("WETH approved for Universal Router");

        uint256 wethBalance = weth.balanceOf(address(this));
        console.log("WETH balance:", wethBalance);
        uint256 allowance = weth.allowance(
            address(this),
            UNIVERSAL_ROUTER_ADDRESS
        );
        console.log("WETH allowance for Universal Router:", allowance);

        // Uniswap V3 Factory address on zkSync
        address factoryAddress = 0x8FdA5a7a8dCA67BBcDd10F02Fa0649A937215422;
        IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);

        address poolAddress = factory.getPool(WETH_ADDRESS, USDC_ADDRESS, 3000);
        require(
            poolAddress != address(0),
            "Pool does not exist for this token pair"
        );
    }

    function testV3SwapExactIn() public {
        // Prepare the parameters for the swap
        address recipient = address(this); // Recipient of the USDC
        uint256 amountIn = 1 ether; // Amount of WETH to swap
        uint256 minAmountOut = 1 * 10 ** 6;

        // Check initial balances
        uint256 initialWethBalance = weth.balanceOf(address(this));
        uint256 initialUsdcBalance = usdc.balanceOf(address(this));

        // Encoded path for the swap (WETH -> USDC, 0.3% fee tier)
        bytes memory path = abi.encodePacked(
            WETH_ADDRESS,
            uint24(3000),
            USDC_ADDRESS
        );

        bytes[] memory inputs = new bytes[](1);
        // Prepare the input bytes for V3_SWAP_EXACT_IN
        inputs[0] = abi.encode(recipient, amountIn, minAmountOut, path, true);

        // Prepare the command for V3_SWAP_EXACT_IN (0x00)
        bytes memory commands = hex"00"; // single command for V3_SWAP_EXACT_IN
        console.log("Executing swap on Universal Router");
        // Execute the Universal Router swap
        universalRouter.execute(commands, inputs, block.timestamp + 15 minutes);
        console.log("Swap executed successfully");
        // Assert that the contract received some USDC
        uint256 usdcBalance = usdc.balanceOf(address(this));
        assertGt(usdcBalance, minAmountOut, "Failed to swap WETH for USDC");

        // Assert that the contract received some USDC
        uint256 finalUsdcBalance = usdc.balanceOf(address(this));
        assertGt(
            finalUsdcBalance,
            initialUsdcBalance + minAmountOut,
            "Failed to swap WETH for USDC"
        );

        // Assert WETH balance decreased by the `amountIn`
        uint256 finalWethBalance = weth.balanceOf(address(this));
        assertEq(
            initialWethBalance - finalWethBalance,
            amountIn,
            "Incorrect WETH deducted"
        );

        // Uniswap V3 Factory address on zkSync
        address factoryAddress = 0x8FdA5a7a8dCA67BBcDd10F02Fa0649A937215422;
        IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);

        // Get the pool address for WETH-USDC with 0.3% fee
        address poolAddress = factory.getPool(WETH_ADDRESS, USDC_ADDRESS, 3000);
        require(
            poolAddress != address(0),
            "Pool does not exist for this token pair"
        );

        // Check the pool's balances after the swap
        uint256 poolWethBalanceAfter = weth.balanceOf(poolAddress);
        uint256 poolUsdcBalanceAfter = usdc.balanceOf(poolAddress);

        // Additional console logs for debugging
        console.log("Final WETH balance:", finalWethBalance);
        console.log("Final USDC balance:", finalUsdcBalance);
        console.log("Pool WETH balance after:", poolWethBalanceAfter);
        console.log("Pool USDC balance after:", poolUsdcBalanceAfter);
    }
}
