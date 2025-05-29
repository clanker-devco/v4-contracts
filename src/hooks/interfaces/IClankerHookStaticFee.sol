// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IClankerHookStaticFee {
    error ClankerFeeTooHigh();
    error PairedFeeTooHigh();

    event PoolInitialized(PoolId poolId, uint24 clankerFee, uint24 pairedFee);

    struct PoolStaticConfigVars {
        uint24 clankerFee;
        uint24 pairedFee;
    }
}
