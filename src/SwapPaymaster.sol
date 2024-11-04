// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap-zksync/interfaces/IUniversalRouter.sol";
import "@uniswap-zksync-router/interfaces/IQuoterV2.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

import "@matterlabs/era-contracts/interfaces/IPaymaster.sol";
import "@matterlabs/era-contracts/interfaces/IPaymasterFlow.sol";
import "@matterlabs/era-contracts/Constants.sol";

import "lib/Permit2/src/interfaces/IPermit2.sol";

import "forge-std/console.sol";

// Define WETH interface to unwrap WETH to ETH
interface IWETH is IERC20 {
    function withdraw(uint256 amount) external;
}

contract DynamicSwapPaymaster is IPaymaster {
    IUniversalRouter public immutable universalRouter;
    IWETH public immutable WETH;
    IQuoterV2 public immutable quoter;
    address public allowedToken;
    IPermit2 private permit2;

    // Constants
    uint24 public constant POOL_FEE = 3000;

    // Mapping to hold supported tokens and their Uniswap pool fees
    mapping(address => uint24) public tokenToFee;

    // Constructor to initialize the Universal Router and WETH contract
    constructor(
        address _universalRouter,
        address _weth,
        address _erc20,
        address _permit2Address,
        address _quoterAddress
    ) {
        universalRouter = IUniversalRouter(_universalRouter);
        WETH = IWETH(_weth);
        allowedToken = _erc20;
        permit2 = IPermit2(_permit2Address);
        quoter = IQuoterV2(_quoterAddress);
    }

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        _;
    }

    // Main function to validate and pay for transactions via the paymaster
    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic, bytes memory context)
    {
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;

        require(
            _transaction.paymasterInput.length >= 4,
            "Invalid paymaster input length"
        );
        // Decode paymaster input
        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );
        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            // Decode the approval-based flow data: token, amount, and additional data
            (address token, uint256 amount, bytes memory data) = abi.decode(
                _transaction.paymasterInput[4:],
                (address, uint256, bytes)
            );

            // Validate token: only allow the predefined token for fee payment
            require(token == allowedToken, "Invalid token for fee payment");

            console.log(
                "transaction from: %s",
                address(uint160(_transaction.from))
            );
            console.log(
                "transaction to: %s",
                address(uint160(_transaction.to))
            );

            // Verify that the user has set sufficient allowance for the paymaster
            address userAddress = address(uint160(_transaction.from));
            address thisAddress = address(this);
            console.log("User address: %s", userAddress);
            console.log("Paymaster address: %s", thisAddress);

            uint256 providedAllowance = IERC20(token).allowance(
                userAddress,
                thisAddress
            );
            require(providedAllowance >= amount, "Insufficient allowance");

            // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
            // neither paymaster nor account are allowed to access this context variable.
            // TODO: investigate why this is massive!
            console.log("Gas limit: %d", _transaction.gasLimit);
            console.log("Max fee per gas: %d", _transaction.maxFeePerGas);
            // Gas limit: 1073741824
            // Max fee per gas: 260000000
            // REQUIRED_ETH = 279172874240000000
            uint256 requiredETH = 2923085 * 45250000;
            // .049 ether seems to lowest amount that works, thats $127.47 USD. Does not make sense?
            uint256 amountIn = calculateTokenAmountForGas(token, .049 ether);
            // TODO: understand approvals better here (should be for amountIn?);
            IERC20(token).approve(address(permit2), type(uint256).max);
            permit2.approve(
                token,
                address(universalRouter),
                type(uint160).max,
                uint48(block.timestamp + 15 minutes)
            );

            try
                IERC20(token).transferFrom(userAddress, thisAddress, amount)
            {} catch (bytes memory revertReason) {
                // If the revert reason is empty or represented by just a function selector,
                // we replace the error with a more user-friendly message
                if (revertReason.length <= 4) {
                    revert("Failed to transferFrom from users' account");
                } else {
                    assembly {
                        revert(add(0x20, revertReason), mload(revertReason))
                    }
                }
            }
            // Swap the approved tokens to ETH
            uint256 ethReceived = swapTokensToETH(token, amountIn, requiredETH);
            console.log("ETH received from swap: %d", ethReceived);

            // Ensure we received enough ETH from the swap
            require(
                ethReceived >= requiredETH,
                "Not enough ETH received from swap"
            );
            // Transfer the ETH to the bootloader to pay for the transaction's gas fees
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
                value: ethReceived
            }("");
            require(
                success,
                "Failed to transfer transaction fee to bootloader. Paymaster balance insufficient."
            );
        } else {
            revert("Unsupported paymaster flow");
        }
    }

    // Function to calculate the exact amount of tokens needed for WETH using QuoterV2
    function calculateTokenAmountForGas(
        address token,
        uint256 ethRequired
    ) internal returns (uint256) {
        uint24 poolFee = tokenToFee[token] != 0 ? tokenToFee[token] : POOL_FEE;

        // Prepare the parameters for the quote
        IQuoterV2.QuoteExactOutputSingleParams memory params = IQuoterV2
            .QuoteExactOutputSingleParams({
                tokenIn: token,
                tokenOut: address(WETH),
                amount: ethRequired,
                fee: poolFee,
                sqrtPriceLimitX96: 0 // No price limit
            });

        // Call the quoter with the parameters
        (uint256 tokenAmountIn, , , ) = quoter.quoteExactOutputSingle(params);

        return tokenAmountIn;
    }

    // Swap user's token to ETH via Uniswap V3 using Universal Router
    function swapTokensToETH(
        address token,
        uint256 tokenAmountIn,
        uint256 ethRequired
    ) internal returns (uint256 ethReceived) {
        // Define the command for a V3 exact input swap
        bytes memory commands = hex"00"; // V3_SWAP_EXACT_IN command

        // Define the path for the swap: token -> WETH
        bytes memory path = abi.encodePacked(
            token,
            uint24(3000),
            address(WETH)
        );

        // Initialize the inputs array with 1 element
        bytes[] memory inputs = new bytes[](1);
        address recipient = address(this);

        // Define the input parameters for the swap
        inputs[0] = abi.encode(
            recipient, // Recipient of the output token (WETH)
            tokenAmountIn, // Amount of input tokens (token) to be swapped
            ethRequired, // Minimum amount of WETH output (slippage handling)
            path, // Path of the swap
            true // Indicates that funds should come from this contract
        );
        console.log("Executing swap on Universal Router");
        // Execute the swap on the Universal Router
        universalRouter.execute(commands, inputs, block.timestamp + 15 minutes);
        console.log("Swap executed successfully");

        // Get the WETH balance of the contract after the swap
        uint256 wethBalance = WETH.balanceOf(address(this));
        console.log("WETH balance after swap: %d", wethBalance);

        // Unwrap WETH to ETH
        WETH.withdraw(wethBalance);

        // Return the amount of ETH received
        return wethBalance;
    }

    // Required post-transaction function for paymasters
    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32,
        bytes32,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable override onlyBootloader {
        // Additional actions after transaction execution, if necessary
    }

    // Receive function to accept ETH
    receive() external payable {}
}
