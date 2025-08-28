// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerMevModule} from "../../interfaces/IClankerMevModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerMevDescendingFees is IClankerMevModule {
    event DecayPeriodOver(PoolId poolId);
    event FeeConfigSet(PoolId poolId, uint24 startingFee, uint24 endingFee, uint256 secondsToDecay);

    error PoolAlreadyInitialized();
    error StartingFeeMustBeGreaterThanZero();
    error StartingFeeMustBeGreaterThanEndingFee();
    error TimeDecayMustBeGreaterThanZero();
    error OnlyClankerHookV2();
    error SameSecondAsDeployment();
    error TimeDecayLongerThanMaxMevDelay();
    error StartingFeeGreaterThanMaxLpFee();

    struct FeeConfig {
        uint24 startingFee;
        uint24 endingFee;
        uint256 secondsToDecay;
    }

    function getFee(PoolId poolId) external view returns (uint24);
}
