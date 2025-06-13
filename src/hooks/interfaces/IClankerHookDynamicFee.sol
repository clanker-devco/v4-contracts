// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IClankerHookDynamicFee {
    error BaseFeeTooLow();
    error MaxLpFeeTooHigh();
    error BaseFeeGreaterThanMaxLpFee();

    event PoolInitialized(
        PoolId poolId,
        uint24 baseFee,
        uint24 maxLpFee,
        uint256 referenceTickFilterPeriod,
        uint256 resetPeriod,
        int24 resetTickFilter,
        uint256 feeControlNumerator,
        uint24 decayFilterBps
    );

    event EstimatedTickDifference(int24 beforeTick, int24 afterTick);

    struct PoolDynamicConfigVars {
        uint24 baseFee;
        uint24 maxLpFee;
        uint256 referenceTickFilterPeriod;
        uint256 resetPeriod;
        int24 resetTickFilter;
        uint256 feeControlNumerator;
        uint24 decayFilterBps;
    }

    struct PoolDynamicFeeVars {
        int24 referenceTick;
        int24 resetTick;
        uint256 resetTickTimestamp;
        uint256 lastSwapTimestamp;
        uint24 appliedVR; // applied volatility reference
        uint24 prevVA; // swap's previous volatility accumulation, used to generate the volatility reference
    }

    function poolConfigVars(PoolId poolId) external view returns (PoolDynamicConfigVars memory);
    function poolFeeVars(PoolId poolId) external view returns (PoolDynamicFeeVars memory);
}
