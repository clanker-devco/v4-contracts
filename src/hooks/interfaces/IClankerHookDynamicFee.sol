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
        uint24 feeControlNumerator;
        uint24 decayFilterBps;
    }
}
