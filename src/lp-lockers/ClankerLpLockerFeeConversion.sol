// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerFeeLocker} from "../interfaces/IClankerFeeLocker.sol";

import {IClankerHook} from "../interfaces/IClankerHook.sol";
import {IClankerLpLocker} from "../interfaces/IClankerLpLocker.sol";
import {IClankerLpLockerFeeConversion} from "./interfaces/IClankerLpLockerFeeConversion.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

contract ClankerLpLockerFeeConversion is IClankerLpLockerFeeConversion, ReentrancyGuard, Ownable {
    using TickMath for int24;
    using BalanceDeltaLibrary for BalanceDelta;

    string public constant version = "1";

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_REWARD_PARTICIPANTS = 7;
    uint256 public constant MAX_LP_POSITIONS = 7;

    IPositionManager public immutable positionManager;
    IPoolManager public immutable poolManager;
    IPermit2 public immutable permit2;
    IClankerFeeLocker public immutable feeLocker;
    IUniversalRouter public immutable universalRouter;
    address public immutable factory;

    // guard to stop recursive collection calls
    bool internal _inCollect;

    mapping(address token => TokenRewardInfo tokenRewardInfo) internal _tokenRewards;
    mapping(address token => FeeIn[] feePreference) public feePreferences;

    constructor(
        address owner_,
        address factory_, // Address of the clanker factory
        address feeLocker_,
        address positionManager_, // Address of the position manager
        address permit2_, // address of the permit2 contract
        address universalRouter_, // address of the universal router
        address poolManager_ // address of the pool manager
    ) Ownable(owner_) {
        factory = factory_;
        feeLocker = IClankerFeeLocker(feeLocker_);
        positionManager = IPositionManager(positionManager_);
        permit2 = IPermit2(permit2_);
        universalRouter = IUniversalRouter(universalRouter_);
        poolManager = IPoolManager(poolManager_);
    }

    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert Unauthorized();
        }
        _;
    }

    function tokenRewards(address token) external view returns (TokenRewardInfo memory) {
        return _tokenRewards[token];
    }

    function placeLiquidity(
        IClanker.LockerConfig memory lockerConfig,
        IClanker.PoolConfig memory poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) external onlyFactory nonReentrant returns (uint256 positionId) {
        // decode the extra locker data
        FeeIn[] memory lpFeeConversionPreferences = abi.decode(
            lockerConfig.lockerData, (IClankerLpLockerFeeConversion.LpFeeConversionInfo)
        ).feePreference;

        // ensure that we don't already have a reward for this token
        if (_tokenRewards[token].positionId != 0) {
            revert TokenAlreadyHasRewards();
        }

        // create the reward info
        TokenRewardInfo memory tokenRewardInfo = TokenRewardInfo({
            token: token,
            poolKey: poolKey,
            positionId: 0, // set below
            numPositions: lockerConfig.tickLower.length,
            rewardBps: lockerConfig.rewardBps,
            rewardAdmins: lockerConfig.rewardAdmins,
            rewardRecipients: lockerConfig.rewardRecipients
        });

        // check that all arrays are the same length
        if (
            tokenRewardInfo.rewardBps.length != tokenRewardInfo.rewardAdmins.length
                || tokenRewardInfo.rewardBps.length != tokenRewardInfo.rewardRecipients.length
                || tokenRewardInfo.rewardBps.length != lpFeeConversionPreferences.length
        ) {
            revert MismatchedRewardArrays();
        }

        // check that the number of reward participants is not greater than the max
        if (tokenRewardInfo.rewardBps.length > MAX_REWARD_PARTICIPANTS) {
            revert TooManyRewardParticipants();
        }

        // check that there is at least one reward
        if (tokenRewardInfo.rewardBps.length == 0) {
            revert NoRewardRecipients();
        }

        // check that the reward amounts add up to 10000
        uint16 totalRewards = 0;
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            totalRewards += tokenRewardInfo.rewardBps[i];
            if (tokenRewardInfo.rewardBps[i] == 0) {
                revert ZeroRewardAmount();
            }
        }
        if (totalRewards != BASIS_POINTS) {
            revert InvalidRewardBps();
        }

        // check that no address is the zero address
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            if (
                tokenRewardInfo.rewardAdmins[i] == address(0)
                    || tokenRewardInfo.rewardRecipients[i] == address(0)
            ) {
                revert ZeroRewardAddress();
            }
        }

        // pull in the token and mint liquidity
        IERC20(token).transferFrom(msg.sender, address(this), poolSupply);
        positionId = _mintLiquidity(poolConfig, lockerConfig, poolKey, poolSupply, token);

        // store the reward info
        tokenRewardInfo.positionId = positionId;
        _tokenRewards[token] = tokenRewardInfo;

        // store the fee preference
        feePreferences[token] = lpFeeConversionPreferences;

        emit TokenRewardAdded({
            token: tokenRewardInfo.token,
            poolKey: tokenRewardInfo.poolKey,
            poolSupply: poolSupply,
            positionId: tokenRewardInfo.positionId,
            numPositions: tokenRewardInfo.numPositions,
            rewardBps: tokenRewardInfo.rewardBps,
            rewardAdmins: tokenRewardInfo.rewardAdmins,
            rewardRecipients: tokenRewardInfo.rewardRecipients,
            tickLower: lockerConfig.tickLower,
            tickUpper: lockerConfig.tickUpper,
            positionBps: lockerConfig.positionBps
        });
    }

    function _mintLiquidity(
        IClanker.PoolConfig memory poolConfig,
        IClanker.LockerConfig memory lockerConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) internal returns (uint256 positionId) {
        // check that all position infos are the same length
        if (
            lockerConfig.tickLower.length != lockerConfig.tickUpper.length
                || lockerConfig.tickLower.length != lockerConfig.positionBps.length
        ) {
            revert MismatchedPositionInfos();
        }

        // ensure that there is at least one position
        if (lockerConfig.tickLower.length == 0) {
            revert NoPositions();
        }

        // ensure that the max number of positions is not exceeded
        if (lockerConfig.tickLower.length > MAX_LP_POSITIONS) {
            revert TooManyPositions();
        }

        // make sure the locker position config is valid
        uint256 positionBpsTotal = 0;
        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            if (lockerConfig.tickLower[i] > lockerConfig.tickUpper[i]) {
                revert TicksBackwards();
            }
            if (
                lockerConfig.tickLower[i] < TickMath.MIN_TICK
                    || lockerConfig.tickUpper[i] > TickMath.MAX_TICK
            ) {
                revert TicksOutOfTickBounds();
            }
            if (
                lockerConfig.tickLower[i] % poolConfig.tickSpacing != 0
                    || lockerConfig.tickUpper[i] % poolConfig.tickSpacing != 0
            ) {
                revert TicksNotMultipleOfTickSpacing();
            }
            if (lockerConfig.tickLower[i] < poolConfig.tickIfToken0IsClanker) {
                revert TickRangeLowerThanStartingTick();
            }

            positionBpsTotal += lockerConfig.positionBps[i];
        }
        if (positionBpsTotal != BASIS_POINTS) {
            revert InvalidPositionBps();
        }

        bool token0IsClanker = token < poolConfig.pairedToken;

        // encode actions
        bytes[] memory params = new bytes[](lockerConfig.tickLower.length + 1);
        bytes memory actions;

        int24 startingTick =
            token0IsClanker ? poolConfig.tickIfToken0IsClanker : -poolConfig.tickIfToken0IsClanker;

        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            // add mint action
            actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));

            // determine token amount for this position
            uint256 tokenAmount = poolSupply * lockerConfig.positionBps[i] / BASIS_POINTS;
            uint256 amount0 = token0IsClanker ? tokenAmount : 0;
            uint256 amount1 = token0IsClanker ? 0 : tokenAmount;

            // determine tick bounds for this position
            int24 tickLower_ =
                token0IsClanker ? lockerConfig.tickLower[i] : -lockerConfig.tickLower[i];
            int24 tickUpper_ =
                token0IsClanker ? lockerConfig.tickUpper[i] : -lockerConfig.tickUpper[i];
            int24 tickLower = token0IsClanker ? tickLower_ : tickUpper_;
            int24 tickUpper = token0IsClanker ? tickUpper_ : tickLower_;
            uint160 lowerSqrtPrice = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 upperSqrtPrice = TickMath.getSqrtPriceAtTick(tickUpper);

            // determine liquidity amount
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                startingTick.getSqrtPriceAtTick(), lowerSqrtPrice, upperSqrtPrice, amount0, amount1
            );

            params[i] = abi.encode(
                poolKey,
                tickLower, // tick lower
                tickUpper, // tick upper
                liquidity, // liquidity
                amount0, // amount0Max
                amount1, // amount1Max
                address(this), // recipient of position
                abi.encode(address(this))
            );
        }

        // add settle action
        actions = abi.encodePacked(actions, uint8(Actions.SETTLE_PAIR));
        params[lockerConfig.tickLower.length] = abi.encode(poolKey.currency0, poolKey.currency1);

        // approvals
        {
            IERC20(token).approve(address(permit2), poolSupply);
            permit2.approve(
                token, address(positionManager), uint160(poolSupply), uint48(block.timestamp)
            );
        }

        // grab position id we're about to mint
        positionId = positionManager.nextTokenId();
        // add liquidity
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    // collect rewards while pool is unlocked (e.g. in an afterSwap hook)
    function collectRewardsWithoutUnlock(address token) external {
        _collectRewards(token, true);
    }

    // collect rewards while pool is locked
    function collectRewards(address token) external {
        _collectRewards(token, false);
    }

    function _mevModuleOperating(address token) internal view returns (bool) {
        // check if the mev module has expired on the token's pool,
        // if it has not, we need to skip the collection as the swap-back
        // can be blocked by the mev module
        PoolId poolId = PoolIdLibrary.toId(_tokenRewards[token].poolKey);

        // if the mev module is disabled, the swap backs cannot be blocked
        if (!IClankerHook(address(_tokenRewards[token].poolKey.hooks)).mevModuleEnabled(poolId)) {
            return false;
        }

        // if the mev module is enabled, check if the pool is older than the max mev module expiry time.
        // if it is, the mev module will not be triggered and the swap backs cannot be blocked
        uint256 poolCreationTimestamp =
            IClankerHook(address(_tokenRewards[token].poolKey.hooks)).poolCreationTimestamp(poolId);
        if (
            poolCreationTimestamp
                + IClankerHook(address(_tokenRewards[token].poolKey.hooks)).MAX_MEV_MODULE_DELAY()
                <= block.timestamp
        ) {
            return false;
        }

        // mev module is enabled and not expired, the swap backs can be blocked
        return true;
    }

    // Collect rewards for a token
    function _collectRewards(address token, bool withoutUnlock) internal {
        if (_inCollect) {
            // stop recursive call
            return;
        }

        // check if the mev module is expired
        if (_mevModuleOperating(token)) {
            // do not perform collection if mev module is still operating
            return;
        }

        _inCollect = true;

        // get the reward info
        TokenRewardInfo memory tokenRewardInfo = _tokenRewards[token];

        // collect the rewards
        (uint256 amount0, uint256 amount1) = _bringFeesIntoContract(
            tokenRewardInfo.poolKey,
            tokenRewardInfo.positionId,
            tokenRewardInfo.numPositions,
            withoutUnlock
        );

        IERC20 rewardToken0 = IERC20(Currency.unwrap(tokenRewardInfo.poolKey.currency0));
        IERC20 rewardToken1 = IERC20(Currency.unwrap(tokenRewardInfo.poolKey.currency1));

        uint256[] memory rewards0 = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256[] memory rewards1 = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256 amount0_actualized = 0;
        uint256 amount1_actualized = 0;

        // handle fees for token0
        if (amount0 > 0) {
            (uint256[] memory _rewards0, uint256[] memory _rewards1) =
                _handleFees(token, address(rewardToken0), amount0, withoutUnlock);
            for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
                rewards0[i] += _rewards0[i];
                rewards1[i] += _rewards1[i];
                amount0_actualized += _rewards0[i];
                amount1_actualized += _rewards1[i];
            }
        }

        // handle fees for token1
        if (amount1 > 0) {
            (uint256[] memory _rewards0, uint256[] memory _rewards1) =
                _handleFees(token, address(rewardToken1), amount1, withoutUnlock);
            for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
                rewards0[i] += _rewards0[i];
                rewards1[i] += _rewards1[i];
                amount0_actualized += _rewards0[i];
                amount1_actualized += _rewards1[i];
            }
        }

        _inCollect = false;

        // emit the claim event
        emit ClaimedRewards(
            tokenRewardInfo.token, amount0_actualized, amount1_actualized, rewards0, rewards1
        );
    }

    // handle fees for a token
    function _handleFees(address token, address rewardToken, uint256 amount, bool withoutUnlock)
        internal
        returns (uint256[] memory, uint256[] memory)
    {
        TokenRewardInfo memory tokenRewardInfo = _tokenRewards[token];
        uint256[] memory rewards0 = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256[] memory rewards1 = new uint256[](tokenRewardInfo.rewardBps.length);

        // if the rewardToken is the clanker, we want to swap for recipients who
        // want their fee in the paired token
        //
        // conversely, if the rewardToken is the paired token, we want to swap for
        // recipients who want their fee in the clanker token
        FeeIn toSwap = token == rewardToken ? FeeIn.Paired : FeeIn.Clanker;
        address tokenToSwapInto =
            token == rewardToken ? _getPairedToken(token, tokenRewardInfo.poolKey) : token;
        bool rewardTokenIsToken0 = rewardToken == Currency.unwrap(tokenRewardInfo.poolKey.currency0);

        // get the reward info
        FeeIn[] memory feePreference = feePreferences[token];

        // determine bps and token amount to swap while distributing the non-swapped portion
        uint256 tokenToSwap = amount;
        uint256 bpsToSwapTotal = 0;
        uint256[] memory toSwapIndexes = new uint256[](feePreference.length);
        uint256[] memory toDistributeIndexes = new uint256[](feePreference.length);
        uint256 toSwapCount = 0;
        uint256 toDistributeCount = 0;

        // determine breakdown of bps to swap and distribute
        for (uint256 i = 0; i < feePreference.length; i++) {
            if (feePreference[i] == toSwap) {
                bpsToSwapTotal += tokenRewardInfo.rewardBps[i];
                toSwapIndexes[toSwapCount] = i;
                toSwapCount++;
            } else {
                toDistributeIndexes[toDistributeCount] = i;
                toDistributeCount++;
            }
        }

        // determine how to handle dust. if there is no recipient requesting a swap,
        // then we handle the dust in the last index of the distribute loop
        uint256 distributeLoop = toSwapCount == 0 ? toDistributeCount - 1 : toDistributeCount;

        // send the non-swapped portion to the recipients in the fee locker
        for (uint256 i = 0; i < distributeLoop; i++) {
            uint256 tokenToDistribute =
                tokenRewardInfo.rewardBps[toDistributeIndexes[i]] * amount / BASIS_POINTS;
            if (tokenToDistribute == 0) {
                continue;
            }

            tokenToSwap -= tokenToDistribute;
            SafeERC20.forceApprove(IERC20(rewardToken), address(feeLocker), tokenToDistribute);
            feeLocker.storeFees(
                tokenRewardInfo.rewardRecipients[toDistributeIndexes[i]],
                address(rewardToken),
                tokenToDistribute
            );
            rewardTokenIsToken0
                ? rewards0[toDistributeIndexes[i]] += tokenToDistribute
                : rewards1[toDistributeIndexes[i]] += tokenToDistribute;
        }

        if (toSwapCount == 0 && tokenToSwap > 0) {
            SafeERC20.forceApprove(IERC20(rewardToken), address(feeLocker), tokenToSwap);
            feeLocker.storeFees(
                tokenRewardInfo.rewardRecipients[toDistributeIndexes[distributeLoop]],
                address(rewardToken),
                tokenToSwap
            );
            rewardTokenIsToken0
                ? rewards0[toDistributeIndexes[distributeLoop]] += tokenToSwap
                : rewards1[toDistributeIndexes[distributeLoop]] += tokenToSwap;
        }

        // swap the remaining reward token
        uint256 swapAmountOut = 0;
        if (toSwapCount > 0) {
            swapAmountOut = withoutUnlock
                ? _uniSwapUnlocked(
                    tokenRewardInfo.poolKey, address(rewardToken), tokenToSwapInto, uint128(tokenToSwap)
                )
                : _uniSwapLocked(
                    tokenRewardInfo.poolKey, address(rewardToken), tokenToSwapInto, uint128(tokenToSwap)
                );

            // record amount distributed so far for dust handling
            uint256 swapDistributed = 0;

            // force approve the fee locker to the swap amount out
            SafeERC20.forceApprove(IERC20(tokenToSwapInto), address(feeLocker), swapAmountOut);

            // distribute the swapped portion to the recipients in the fee locker
            for (uint256 i = 0; i < toSwapCount - 1; i++) {
                uint256 tokenToDistribute =
                    tokenRewardInfo.rewardBps[toSwapIndexes[i]] * swapAmountOut / BASIS_POINTS;
                if (tokenToDistribute == 0) {
                    continue;
                }

                swapDistributed += tokenToDistribute;
                feeLocker.storeFees(
                    tokenRewardInfo.rewardRecipients[toSwapIndexes[i]],
                    address(tokenToSwapInto),
                    tokenToDistribute
                );
                rewardTokenIsToken0
                    ? rewards1[toSwapIndexes[i]] += tokenToDistribute
                    : rewards0[toSwapIndexes[i]] += tokenToDistribute;
            }

            // distribute the fees and dust to the last swap recipient
            uint256 tokenToDistribute = swapAmountOut - swapDistributed;
            if (tokenToDistribute != 0) {
                feeLocker.storeFees(
                    tokenRewardInfo.rewardRecipients[toSwapIndexes[toSwapCount - 1]],
                    address(tokenToSwapInto),
                    tokenToDistribute
                );

                rewardTokenIsToken0
                    ? rewards1[toSwapIndexes[toSwapCount - 1]] += tokenToDistribute
                    : rewards0[toSwapIndexes[toSwapCount - 1]] += tokenToDistribute;
            }

            emit FeesSwapped(token, rewardToken, tokenToSwap, tokenToSwapInto, swapAmountOut);
        }

        return (rewards0, rewards1);
    }

    function _bringFeesIntoContract(
        PoolKey memory poolKey,
        uint256 positionId,
        uint256 numPositions,
        bool withoutUnlock
    ) internal returns (uint256 amount0, uint256 amount1) {
        bytes memory actions;
        bytes[] memory params = new bytes[](numPositions + 1);

        for (uint256 i = 0; i < numPositions; i++) {
            actions = abi.encodePacked(actions, uint8(Actions.DECREASE_LIQUIDITY));
            /// @dev collecting fees is achieved with liquidity=0, the second parameter
            params[i] = abi.encode(positionId + i, 0, 0, 0, abi.encode());
        }

        Currency currency0 = poolKey.currency0;
        Currency currency1 = poolKey.currency1;
        actions = abi.encodePacked(actions, uint8(Actions.TAKE_PAIR));
        params[numPositions] = abi.encode(currency0, currency1, address(this));

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // when claiming from the hook, we need to call modifyLiquiditiesWithoutUnlock since
        // the pool will be in an unlocked state
        if (withoutUnlock) {
            positionManager.modifyLiquiditiesWithoutUnlock(actions, params);
        } else {
            positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
        }

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        return (balance0After - balance0Before, balance1After - balance1Before);
    }

    // perform a swap on the pool directly while it is unlocked
    function _uniSwapUnlocked(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint128 amountIn
    ) internal returns (uint256) {
        bool zeroForOne = tokenIn < tokenOut;

        // Build swap request
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(int128(amountIn)),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        // record before token balance
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(this));

        // Execute the swap
        BalanceDelta delta = poolManager.swap(poolKey, swapParams, abi.encode());

        // determine swap outcomes
        int128 deltaOut = delta.amount0() < 0 ? delta.amount1() : delta.amount0();

        // pay the input token
        poolManager.sync(Currency.wrap(tokenIn));
        Currency.wrap(tokenIn).transfer(address(poolManager), amountIn);
        poolManager.settle();

        // take out the converted token
        poolManager.take(Currency.wrap(tokenOut), address(this), uint256(uint128(deltaOut)));

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(address(this));
        return tokenOutAfter - tokenOutBefore;
    }

    // perform a swap using the universal router which handles the unlocking of the pool
    function _uniSwapLocked(
        PoolKey memory poolKey,
        address tokenIn,
        address tokenOut,
        uint128 amountIn
    ) internal returns (uint256) {
        // initiate a swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);

        // First parameter: SWAP_EXACT_IN_SINGLE
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenIn < tokenOut, // swapping tokenIn -> tokenOut
                amountIn: amountIn, // amount of tokenIn to swap
                amountOutMinimum: 0, // minimum amount we expect to receive
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

        // approvals
        SafeERC20.forceApprove(IERC20(tokenIn), address(permit2), amountIn);
        permit2.approve(tokenIn, address(universalRouter), amountIn, uint48(block.timestamp));

        // Execute the swap
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp);

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(address(this));

        return tokenOutAfter - tokenOutBefore;
    }

    function _getPairedToken(address token, PoolKey memory poolKey)
        internal
        view
        returns (address)
    {
        return Currency.unwrap(poolKey.currency0) == token
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);
    }

    // Replace the reward recipient
    function updateRewardRecipient(address token, uint256 rewardIndex, address newRecipient)
        external
    {
        TokenRewardInfo storage tokenRewardInfo = _tokenRewards[token];

        // Only admin can replace the reward recipient
        if (msg.sender != tokenRewardInfo.rewardAdmins[rewardIndex]) {
            revert Unauthorized();
        }

        // Add the new recipient
        address oldRecipient = tokenRewardInfo.rewardRecipients[rewardIndex];
        tokenRewardInfo.rewardRecipients[rewardIndex] = newRecipient;

        emit RewardRecipientUpdated(token, rewardIndex, oldRecipient, newRecipient);
    }

    function updateFeePreference(address token, uint256 rewardIndex, FeeIn newFeePreference)
        external
    {
        TokenRewardInfo storage tokenRewardInfo = _tokenRewards[token];

        // Only admin can update the fee preference
        if (msg.sender != tokenRewardInfo.rewardAdmins[rewardIndex]) {
            revert Unauthorized();
        }

        // grab the old fee preference
        FeeIn oldFeePreference = feePreferences[token][rewardIndex];

        // update the fee preference
        feePreferences[token][rewardIndex] = newFeePreference;
        emit FeePreferenceUpdated(token, rewardIndex, oldFeePreference, newFeePreference);
    }

    // Replace the reward admin
    function updateRewardAdmin(address token, uint256 rewardIndex, address newAdmin) external {
        TokenRewardInfo storage tokenRewardInfo = _tokenRewards[token];

        // Only admin can replace the reward recipient
        if (msg.sender != tokenRewardInfo.rewardAdmins[rewardIndex]) {
            revert Unauthorized();
        }

        // Add the new recipient
        address oldAdmin = tokenRewardInfo.rewardAdmins[rewardIndex];
        tokenRewardInfo.rewardAdmins[rewardIndex] = newAdmin;

        emit RewardAdminUpdated(token, rewardIndex, oldAdmin, newAdmin);
    }

    // Enable contract to receive LP Tokens
    function onERC721Received(address, address from, uint256 id, bytes calldata)
        external
        returns (bytes4)
    {
        // Only Clanker Factory can send NFTs here
        if (from != factory) {
            revert Unauthorized();
        }

        emit Received(from, id);
        return IERC721Receiver.onERC721Received.selector;
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner nonReentrant {
        payable(recipient).transfer(address(this).balance);
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address token, address recipient) public onlyOwner nonReentrant {
        IERC20 token_ = IERC20(token);
        SafeERC20.safeTransfer(token_, recipient, token_.balanceOf(address(this)));
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IClankerLpLocker).interfaceId;
    }
}
