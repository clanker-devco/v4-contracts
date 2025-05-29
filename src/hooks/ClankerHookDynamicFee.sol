// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ClankerHook} from "./ClankerHook.sol";

import {IClankerHookDynamicFee} from "./interfaces/IClankerHookDynamicFee.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract ClankerHookDynamicFee is ClankerHook, IClankerHookDynamicFee {
    using StateLibrary for IPoolManager;

    uint24 public constant BPS_DENOMINATOR = 10_000;
    uint24 public constant MIN_BASE_FEE = 2500; // 0.025%;
    uint256 public constant MAX_DECAY_FILTER_BPS = 30_000;
    uint24 public constant FEE_CONTROL_DENOMINATOR = 1_000_000;

    mapping(PoolId => PoolDynamicFeeVars) public poolFeeVars;
    mapping(PoolId => PoolDynamicConfigVars) public poolConfigVars;

    struct PoolDynamicFeeVars {
        int24 referenceTick;
        int24 resetTick;
        uint256 resetTickTimestamp;
        uint256 lastSwapTimestamp;
        uint24 appliedVR; // applied volatility reference
        uint24 prevVA; // swap's previous volatility accumulation, used to generate the volatility reference
    }

    error TickReturned(int24 tick);

    constructor(address _poolManager, address _factory, address _locker, address _weth)
        ClankerHook(_poolManager, _factory, _locker, _weth)
    {}

    function _initializePoolData(PoolKey memory poolKey, bytes memory poolData) internal override {
        PoolDynamicConfigVars memory _poolConfigVars = abi.decode(poolData, (PoolDynamicConfigVars));

        if (_poolConfigVars.baseFee < MIN_BASE_FEE) {
            revert BaseFeeTooLow();
        }

        if (_poolConfigVars.maxLpFee > MAX_LP_FEE) {
            revert MaxLpFeeTooHigh();
        }

        if (_poolConfigVars.baseFee > _poolConfigVars.maxLpFee) {
            revert BaseFeeGreaterThanMaxLpFee();
        }

        emit PoolInitialized({
            poolId: poolKey.toId(),
            baseFee: _poolConfigVars.baseFee,
            maxLpFee: _poolConfigVars.maxLpFee,
            referenceTickFilterPeriod: _poolConfigVars.referenceTickFilterPeriod,
            feeControlNumerator: _poolConfigVars.feeControlNumerator,
            decayFilterBps: _poolConfigVars.decayFilterBps,
            resetPeriod: _poolConfigVars.resetPeriod,
            resetTickFilter: _poolConfigVars.resetTickFilter
        });

        poolConfigVars[poolKey.toId()] = _poolConfigVars;
    }

    // set the fee based on the tick after the swap
    function _setFee(PoolKey calldata poolKey, IPoolManager.SwapParams calldata swapParams)
        internal
        override
    {
        uint256 volAccumulator = _getVolatilityAccumulator(poolKey, swapParams);
        uint24 lpFee = _getLpFee(volAccumulator, poolKey.toId());
        _setProtocolFee(lpFee);

        IPoolManager(poolManager).updateDynamicLPFee(poolKey, uint24(lpFee));
    }

    function _getLpFee(uint256 volAccumulator, PoolId poolId) internal returns (uint24 lpFee) {
        PoolDynamicConfigVars storage poolConfigVars_ = poolConfigVars[poolId];
        uint256 variableFee = uint256(poolConfigVars_.feeControlNumerator) * (volAccumulator ** 2)
            / FEE_CONTROL_DENOMINATOR;

        uint256 fee = variableFee + poolConfigVars_.baseFee;
        fee = fee > poolConfigVars_.maxLpFee ? poolConfigVars_.maxLpFee : fee;

        return uint24(fee);
    }

    function _getVolatilityAccumulator(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata swapParams
    ) internal returns (uint24 volatilityAccumulator) {
        PoolId poolId = poolKey.toId();
        PoolDynamicFeeVars storage poolFVars = poolFeeVars[poolId];
        PoolDynamicConfigVars storage poolCVars = poolConfigVars[poolId];
        // grab the tick before the swap
        (, int24 tickBefore,,) = poolManager.getSlot0(poolId);

        // reset the reference tick if the tick filter period has passed
        if (poolFVars.lastSwapTimestamp + poolCVars.referenceTickFilterPeriod < block.timestamp) {
            // set the reference tick to the tick before the swap
            poolFVars.referenceTick = tickBefore;

            // set the reset tick to the tick before the swap and record the reset timestamp
            poolFVars.resetTick = tickBefore;
            poolFVars.resetTickTimestamp = block.timestamp;

            // if the reset period has NOT passed but the tick filter period has, trigger
            // the volatility decay process
            if (poolFVars.lastSwapTimestamp + poolCVars.resetPeriod > block.timestamp) {
                // do math in uint256 to avoid overflow
                uint256 appliedVR = (uint256(poolFVars.prevVA) * uint256(poolCVars.decayFilterBps))
                    / BPS_DENOMINATOR;
                if (appliedVR > type(uint24).max) {
                    poolFVars.appliedVR = type(uint24).max;
                } else {
                    poolFVars.appliedVR = uint24(appliedVR);
                }
            } else {
                poolFVars.appliedVR = 0;
            }

            // set estimated fee for getting simulation closer to actual result
            uint24 approxLPFee = _getLpFee(poolFVars.appliedVR, poolId);
            _setProtocolFee(approxLPFee);
            IPoolManager(poolManager).updateDynamicLPFee(poolKey, approxLPFee);
        } // if we didn't just reset, check if the reset period has passed
        else if (poolFVars.resetTickTimestamp + poolCVars.resetPeriod < block.timestamp) {
            // check if the tick difference is greater than the reset tick filter
            int24 resetTickDifference = tickBefore > poolFVars.resetTick
                ? tickBefore - poolFVars.resetTick
                : poolFVars.resetTick - tickBefore;

            if (resetTickDifference > poolCVars.resetTickFilter) {
                // the tick difference is large enough, don't kill the reference tick
                poolFVars.resetTick = tickBefore;
                poolFVars.resetTickTimestamp = block.timestamp;
            } else {
                // the tick difference is not large enough, clear the stored volatility
                poolFVars.referenceTick = tickBefore;
                poolFVars.resetTick = tickBefore;
                poolFVars.resetTickTimestamp = block.timestamp;
                poolFVars.appliedVR = 0;

                // clear out fee for simulation
                uint24 approxLPFee = poolCVars.baseFee;
                _setProtocolFee(approxLPFee);
                IPoolManager(poolManager).updateDynamicLPFee(poolKey, approxLPFee);
            }
        }
        // update the reference tick timestamp
        poolFVars.lastSwapTimestamp = block.timestamp;

        // find the tick after via simulation
        int24 tickAfter = _getTicks(poolKey, swapParams);

        // calculate the tick difference to use in the volatility equation
        uint24 tickDifference = (poolFVars.referenceTick - tickAfter) > 0
            ? uint24(poolFVars.referenceTick - tickAfter)
            : uint24(tickAfter - poolFVars.referenceTick);

        // apply volatility decay
        // do math in uint256 to avoid overflow
        uint256 volatilityAccumulator_ = (uint256(tickDifference) + uint256(poolFVars.appliedVR));
        if (volatilityAccumulator_ > type(uint24).max) {
            volatilityAccumulator = type(uint24).max;
        } else {
            volatilityAccumulator = uint24(volatilityAccumulator_);
        }
        poolFVars.prevVA = volatilityAccumulator;

        emit EstimatedTickDifference(tickBefore, tickAfter);
    }

    function _getTicks(PoolKey calldata poolKey, IPoolManager.SwapParams calldata swapParams)
        internal
        returns (int24 tickAfter)
    {
        // simulate swap to get the estimated end tick
        //
        // note: this is not going to exactly match the result tick,
        // if we apply a fee change based on this outcome, the resulting
        // tick of the swap could be shifted
        try this.simulateSwap(poolKey, swapParams) {
            revert("simulate swap should fail");
        } catch (bytes memory reason) {
            // Decode the selector (first 4 bytes)
            bytes4 selector = bytes4(reason);

            if (selector != TickReturned.selector) {
                revert("returned selector should be TickReturned");
            }

            // Decode the uint24 value (assuming it's at the end)
            assembly {
                // If we're looking at the last 32 bytes, we need to position our pointer
                // reason + 32 (to skip length) + reason.length - 32 (to get to the last 32 bytes)
                let lastWordPtr := add(add(reason, 32), sub(mload(reason), 32))

                // For uint24, we only need the last 3 bytes of the last word
                // This assumes the uint24 is right-aligned in the last word
                let lastWord := mload(lastWordPtr)

                // Mask to get only the last 3 bytes (24 bits)
                tickAfter := and(lastWord, 0xFFFFFF)
            }
        }
    }

    function simulateSwap(PoolKey calldata poolKey, IPoolManager.SwapParams calldata swapParams)
        external
    {
        if (msg.sender != address(this)) {
            revert("simulateSwap can only be called by the hook");
        }

        // run the swap
        poolManager.swap(poolKey, swapParams, abi.encode());

        // get the tick after the swap
        (, int24 tickAfter,,) = poolManager.getSlot0(poolKey.toId());

        // return the tick post-swap
        revert TickReturned(tickAfter);
    }
}
