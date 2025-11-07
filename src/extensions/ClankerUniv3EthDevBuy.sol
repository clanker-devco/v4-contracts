// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerExtension} from "../interfaces/IClankerExtension.sol";

import {ISwapRouterV3} from "../utils/ISwapRouterV3.sol";
import {IClankerUniv3EthDevBuy} from "./interfaces/IClankerUniv3EthDevBuy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

contract ClankerUniv3EthDevBuy is ReentrancyGuard, IClankerUniv3EthDevBuy {
    IClanker public immutable factory;
    IWETH9 public immutable weth;
    IUniversalRouter public immutable universalRouter;
    IPermit2 public immutable permit2;
    ISwapRouterV3 public immutable swapRouter;

    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert Unauthorized();
        _;
    }

    constructor(
        address factory_,
        address weth_,
        address universalRouter_,
        address permit2_,
        address swapRouter_
    ) {
        factory = IClanker(factory_);
        weth = IWETH9(weth_);
        universalRouter = IUniversalRouter(universalRouter_);
        permit2 = IPermit2(permit2_);
        swapRouter = ISwapRouterV3(swapRouter_);
    }

    function receiveTokens(
        IClanker.DeploymentConfig calldata deploymentConfig,
        PoolKey memory tokenPoolKey,
        address token,
        uint256 extensionSupply,
        uint256 extensionIndex
    ) external payable nonReentrant onlyFactory {
        // ensure that the msgValue matches what was requested and is not zero
        if (
            deploymentConfig.extensionConfigs[extensionIndex].msgValue != msg.value
                || deploymentConfig.extensionConfigs[extensionIndex].msgValue == 0
        ) {
            revert IClankerExtension.InvalidMsgValue();
        }

        // check the vault percentage is zero
        if (
            deploymentConfig.extensionConfigs[extensionIndex].extensionBps != 0
                || extensionSupply != 0
        ) {
            revert InvalidEthDevBuyPercentage();
        }

        // decode the dev buy data
        Univ3EthDevBuyExtensionData memory devBuyData = abi.decode(
            deploymentConfig.extensionConfigs[extensionIndex].extensionData,
            (Univ3EthDevBuyExtensionData)
        );

        // perform the dev buy
        uint256 tokenAmount = _performDevBuy(
            token,
            tokenPoolKey,
            deploymentConfig.poolConfig.pairedToken,
            devBuyData.uniV3Fee,
            devBuyData.pairedTokenAmountOutMinimum
        );

        // transfer the token to the recipient
        IERC20(token).transfer(devBuyData.recipient, tokenAmount);

        emit EthDevBuy(token, devBuyData.recipient, msg.value, tokenAmount);
    }

    function _performDevBuy(
        address token,
        PoolKey memory tokenPoolKey, // pool key of the new token
        address pairedToken,
        uint24 uniV3Fee,
        uint128 pairedTokenAmountOutMinimum
    ) internal returns (uint256) {
        uint128 amountPairedToken = uint128(msg.value);

        // if the paired token is not weth, we need to swap from weth to paired token on a univ3 pool
        if (pairedToken != address(weth)) {
            // the router will find the correct pool based on the fee/token pairing
            // swap from weth to paired token
            ISwapRouterV3.ExactInputSingleParams memory swapParams = ISwapRouterV3
                .ExactInputSingleParams({
                tokenIn: address(weth), // The token we are exchanging from (ETH wrapped as WETH)
                tokenOut: pairedToken, // The token we are exchanging to
                fee: uniV3Fee, // The pool fee
                recipient: address(this), // The recipient address
                amountIn: msg.value, // The amount of ETH (WETH) to be swapped
                amountOutMinimum: pairedTokenAmountOutMinimum, // Minimum amount to receive
                sqrtPriceLimitX96: 0 // No price limit
            });

            // execute the swap to get pair tokens for the initial buy
            amountPairedToken = uint128(swapRouter.exactInputSingle{value: msg.value}(swapParams));
        }

        // if paired is weth, swap from ETH to weth
        // note: univ4 supports ETH as a currency, but we only allow WETH
        if (pairedToken == address(weth)) {
            weth.deposit{value: amountPairedToken}();
        }

        // approve the paired token to be spent by the router
        IERC20(pairedToken).approve(address(permit2), amountPairedToken);
        permit2.approve(
            pairedToken, address(universalRouter), amountPairedToken, uint48(block.timestamp)
        );

        // swap from paired token to new token
        return _univ4Swap(tokenPoolKey, pairedToken, token, amountPairedToken, 1);
    }

    // perform a swap using the universal router
    function _univ4Swap(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint128 amountOutMinimum
    ) internal returns (uint256) {
        // initiate a swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);

        // token ordering
        bool tokenInIsToken0 = Currency.unwrap(poolKey.currency0) == tokenIn;

        // First parameter: SWAP_EXACT_IN_SINGLE
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenInIsToken0 ? true : false, // swapping tokenIn -> tokenOut
                amountIn: amountIn, // amount of tokenIn to swap
                amountOutMinimum: amountOutMinimum, // minimum amount we expect to receive
                hookData: bytes("") // no hook data needed, assuming we're using simple hooks
            })
        );

        // Second parameter: SETTLE_ALL
        params[1] = abi.encode(tokenIn, uint256(amountIn));

        // Third parameter: TAKE_ALL
        params[2] = abi.encode(tokenOut, 1);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(this));

        universalRouter.execute{
            value: Currency.unwrap(poolKey.currency0) == address(0) ? amountIn : 0
        }(commands, inputs, block.timestamp);

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(address(this));

        return tokenOutAfter - tokenOutBefore;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerExtension).interfaceId;
    }
}
