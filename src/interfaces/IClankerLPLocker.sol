// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerLpLocker {
    struct TokenRewardInfo {
        address token;
        PoolKey poolKey;
        uint256 positionId;
        uint256 numPositions;
        uint16[] rewardBps;
        address[] rewardAdmins;
        address[] rewardRecipients;
    }

    event TokenRewardAdded(
        address token,
        PoolKey poolKey,
        uint256 poolSupply,
        uint256 positionId,
        uint256 numPositions,
        uint16[] rewardBps,
        address[] rewardAdmins,
        address[] rewardRecipients,
        int24[] tickLower,
        int24[] tickUpper,
        uint16[] positionBps
    );

    event ClaimedRewards(
        address indexed token,
        uint256 amount0,
        uint256 amount1,
        uint256[] rewards0,
        uint256[] rewards1
    );

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

    // get the reward info for a token
    function tokenRewards(address token) external view returns (TokenRewardInfo memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
