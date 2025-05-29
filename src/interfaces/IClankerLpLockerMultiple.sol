// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerLpLocker} from "./IClankerLpLocker.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerLpLockerMultiple is IClankerLpLocker {
    struct TokenRewardInfo {
        address token;
        PoolKey poolKey;
        uint256 positionId;
        uint256 numPositions;
        uint16[] rewardBps;
        address[] rewardAdmins;
        address[] rewardRecipients;
    }

    error Unauthorized();
    error MismatchedRewardArrays();
    error InvalidRewardBps();
    error ZeroRewardAddress();
    error ZeroRewardAmount();
    error TooManyRewardParticipants();
    error NoRewardRecipients();
    error TokenAlreadyHasRewards();
    error TicksBackwards();
    error TicksOutOfTickBounds();
    error TicksNotMultipleOfTickSpacing();
    error TickRangeLowerThanStartingTick();
    error InvalidPositionBps();
    error MismatchedPositionInfos();
    error NoPositions();
    error TooManyPositions();

    event ClaimedRewards(
        address token, uint256 amount0, uint256 amount1, uint256[] rewards0, uint256[] rewards1
    );

    event Received(address indexed from, uint256 positionId);
    event RewardRecipientUpdated(
        address token, uint256 rewardIndex, address oldRecipient, address newRecipient
    );
    event RewardAdminUpdated(
        address token, uint256 rewardIndex, address oldAdmin, address newAdmin
    );

    event TokenRewardAdded(
        address token,
        PoolKey poolKey,
        uint256 positionId,
        uint256 numPositions,
        uint16[] rewardBps,
        address[] rewardAdmins,
        address[] rewardRecipients,
        int24[] tickLower,
        int24[] tickUpper,
        uint16[] positionBps
    );

    function updateRewardAdmin(address token, uint256 rewardIndex, address newAdmin) external;

    function updateRewardRecipient(address token, uint256 rewardIndex, address newRecipient)
        external;
}
