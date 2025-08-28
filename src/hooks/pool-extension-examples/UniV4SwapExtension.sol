// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../../interfaces/IClanker.sol";
import {IClankerFeeLocker} from "../../interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "../../interfaces/IClankerLpLocker.sol";
import {IClankerLpLockerFeeConversion} from
    "../../lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";
import {IClankerHookV2} from "../interfaces/IClankerHookV2.sol";

import {IClankerHookV2PoolExtension} from "../interfaces/IClankerHookV2PoolExtension.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// example pool extension that takes fees generated for a fee recipient and
// swaps them for a different token
contract UniV4SwapExtension is IClankerHookV2PoolExtension, Ownable {
    error ClankerNotPairedWithTargetInputToken();
    error InvalidFirstFeeRecipient();
    error InvalidFirstFeeAdmin();
    error InvalidFirstFeePreference();
    error OnlyApprovedHooks();
    error InvalidPoolKey();

    event PoolInitialized(PoolId poolId, address clanker, uint16 feeBps);
    event BuyBackRecipientSet(address previousBuyBackRecipient, address newBuyBackRecipient);
    event HookApproved(address hook);
    event SwappedBack(address inputToken, address outputToken, uint256 amountIn, uint256 amountOut);

    IClanker immutable clankerFactory;
    IClankerFeeLocker immutable feeLocker;
    IUniversalRouter immutable universalRouter;
    IPoolManager immutable poolManager;
    // addresses of hooks allowed to call the afterSwap function
    mapping(address hook => bool approved) public approvedHooks;

    address public immutable inputToken;
    address public immutable outputToken;
    // univ4 pool to swap fee token for
    PoolKey public swappingPoolKey;

    // address to receive the bought tokens
    address public buyBackRecipient;

    constructor(
        address _owner,
        address _clankerFactory,
        address _feeLocker,
        address _poolManager,
        address _universalRouter,
        PoolKey memory _swappingPoolKey,
        address _inputToken,
        address _outputToken,
        address _buyBackRecipient,
        address[] memory _approvedHooks
    ) Ownable(_owner) {
        clankerFactory = IClanker(_clankerFactory);
        feeLocker = IClankerFeeLocker(_feeLocker);

        inputToken = _inputToken;
        outputToken = _outputToken;
        swappingPoolKey = _swappingPoolKey;
        poolManager = IPoolManager(_poolManager);
        universalRouter = IUniversalRouter(_universalRouter);

        // assert that the input and output tokens are present in the pool key
        address token0 = Currency.unwrap(_swappingPoolKey.currency0);
        address token1 = Currency.unwrap(_swappingPoolKey.currency1);
        if (
            !(
                (token0 == _inputToken && token1 == _outputToken)
                    || (token0 == _outputToken && token1 == _inputToken)
            )
        ) {
            revert InvalidPoolKey();
        }

        buyBackRecipient = _buyBackRecipient;
        for (uint256 i = 0; i < _approvedHooks.length; i++) {
            approvedHooks[_approvedHooks[i]] = true;
        }
    }

    modifier onlyApprovedHooks() {
        if (!approvedHooks[msg.sender]) {
            revert OnlyApprovedHooks();
        }
        _;
    }

    // change the address that receives the bought back fees
    function setBuyBackRecipient(address _buyBackRecipient) external onlyOwner {
        address previousBuyBackRecipient = buyBackRecipient;
        buyBackRecipient = _buyBackRecipient;
        emit BuyBackRecipientSet(previousBuyBackRecipient, buyBackRecipient);
    }

    // add new hooks the the approved hooks list
    function approveHook(address _hook) external onlyOwner {
        approvedHooks[_hook] = true;
        emit HookApproved(_hook);
    }

    // initialize the user extension with passed in data, called once per pool
    function initializePreLockerSetup(PoolKey calldata, bool, bytes calldata)
        external
        onlyApprovedHooks
    {}

    function initializePostLockerSetup(
        PoolKey calldata poolKey,
        address lpLocker,
        bool clankerIsToken0
    ) external onlyApprovedHooks {
        // grab the deployed clanker and paired token
        address clanker = clankerIsToken0
            ? Currency.unwrap(poolKey.currency0)
            : Currency.unwrap(poolKey.currency1);
        address pairedToken = clankerIsToken0
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);

        // check that the token's paired token is the input token
        if (pairedToken != inputToken) {
            revert ClankerNotPairedWithTargetInputToken();
        }

        // get reward info from the locker
        IClankerLpLocker.TokenRewardInfo memory tokenRewardInfo =
            IClankerLpLocker(lpLocker).tokenRewards(clanker);

        // check that the token reward recipient is this address
        if (tokenRewardInfo.rewardRecipients[0] != address(this)) {
            revert InvalidFirstFeeRecipient();
        }

        // check that the token reward admin is the dead address to prevent the
        // reward recipient from being updated
        if (tokenRewardInfo.rewardAdmins[0] != address(0x000000000000000000000000000000000000dEaD))
        {
            revert InvalidFirstFeeAdmin();
        }

        // check that this fee recipient is only getting the fees in paired token
        if (
            IClankerLpLockerFeeConversion(lpLocker).feePreferences(clanker, 0)
                != IClankerLpLockerFeeConversion.FeeIn.Paired
        ) {
            revert InvalidFirstFeePreference();
        }

        // log fee BPS for observability
        uint16 feeBps = tokenRewardInfo.rewardBps[0];

        // assert that the pool keys are different, this pathway isn't tested
        if (
            uint256(PoolId.unwrap(poolKey.toId())) == uint256(PoolId.unwrap(swappingPoolKey.toId()))
        ) {
            revert InvalidPoolKey();
        }

        emit PoolInitialized(poolKey.toId(), clanker, feeBps);
    }

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bool,
        bytes calldata
    ) external onlyApprovedHooks {
        // claim rewards from the locker
        if (feeLocker.availableFees(address(this), inputToken) > 0) {
            feeLocker.claim(address(this), inputToken);
        }

        // if we have no fees to swap, return
        if (IERC20(inputToken).balanceOf(address(this)) == 0) {
            return;
        }

        // grab amount of token to use for the swap
        uint256 amountIn = IERC20(inputToken).balanceOf(address(this));

        // swap the fees for the output token
        uint256 amountOut = _uniSwapUnlocked(uint128(amountIn));

        // send the output token to the buy back recipient
        IERC20(outputToken).transfer(buyBackRecipient, amountOut);

        // record the amount swapped
        emit SwappedBack(inputToken, outputToken, amountIn, amountOut);
    }

    // perform a swap on the pool while it is unlocked
    function _uniSwapUnlocked(uint128 amountIn) internal returns (uint256) {
        bool zeroForOne = inputToken < outputToken;

        // Build swap request
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(int128(amountIn)),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        // record before token balance
        uint256 outputTokenBefore = IERC20(outputToken).balanceOf(address(this));

        // Execute the swap
        BalanceDelta delta = poolManager.swap(swappingPoolKey, swapParams, abi.encode());

        // determine swap outcomes
        int128 deltaOut = delta.amount0() < 0 ? delta.amount1() : delta.amount0();

        // pay the input token
        poolManager.sync(Currency.wrap(inputToken));
        Currency.wrap(inputToken).transfer(address(poolManager), amountIn);
        poolManager.settle();

        // take out the converted token
        poolManager.take(Currency.wrap(outputToken), address(this), uint256(uint128(deltaOut)));

        uint256 outputTokenAfter = IERC20(outputToken).balanceOf(address(this));
        return outputTokenAfter - outputTokenBefore;
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner {
        (bool success,) = payable(recipient).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address token, address recipient) public onlyOwner {
        IERC20 token_ = IERC20(token);
        SafeERC20.safeTransfer(token_, recipient, token_.balanceOf(address(this)));
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
