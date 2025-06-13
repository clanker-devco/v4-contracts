// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerLpLocker} from "../../interfaces/IClankerLpLocker.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerLpLockerMultiple is IClankerLpLocker {
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

    event Received(address indexed from, uint256 positionId);
    event RewardRecipientUpdated(
        address indexed token,
        uint256 indexed rewardIndex,
        address oldRecipient,
        address newRecipient
    );
    event RewardAdminUpdated(
        address indexed token, uint256 indexed rewardIndex, address oldAdmin, address newAdmin
    );

    function updateRewardAdmin(address token, uint256 rewardIndex, address newAdmin) external;

    function updateRewardRecipient(address token, uint256 rewardIndex, address newRecipient)
        external;
}
