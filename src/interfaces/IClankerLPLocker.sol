// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "./IClanker.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerLpLocker {
    // pull rewards from the uniswap v4 pool into the locker
    function collectRewards(address token) external;

    // pull rewards from the uniswap v4 pool into the locker while
    // the pool is unlocked
    function collectRewardsWithoutUnlock(address token) external;

    // take liqudity from the factory and place it into a pool
    function placeLiquidity(
        IClanker.LockerConfig memory lockerConfig,
        IClanker.PoolConfig memory poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) external returns (uint256 tokenId);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
