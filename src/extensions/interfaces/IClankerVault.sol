// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";

interface IClankerVault is IClankerExtension {
    struct VaultExtensionData {
        address admin;
        uint256 lockupDuration;
        uint256 vestingDuration;
    }

    struct Allocation {
        address token;
        uint256 amountTotal;
        uint256 amountClaimed;
        uint256 lockupEndTime;
        uint256 vestingEndTime;
        address admin;
    }

    error Unauthorized();
    error NoBalanceToClaim();
    error AllocationNotUnlocked();
    error InvalidVaultBps();
    error InvalidVaultAdmin();
    error AllocationAlreadyExists();
    error TransferFailed();
    error VaultLockupDurationTooShort();

    event AllocationCreated(
        address indexed token,
        address indexed admin,
        uint256 supply,
        uint256 lockupDuration,
        uint256 vestingDuration
    );

    event AllocationAdminUpdated(
        address indexed token, address indexed oldAdmin, address indexed newAdmin
    );

    event AllocationClaimed(address indexed token, uint256 amount, uint256 remainingAmount);

    function allocation(address token)
        external
        view
        returns (
            address tokenAddress,
            uint256 amountTotal,
            uint256 amountClaimed,
            uint256 lockupEndTime,
            uint256 vestingEndTime,
            address admin
        );

    function editAllocationAdmin(address token, address newAdmin) external;
    function amountAvailableToClaim(address token) external view returns (uint256);
    function claim(address token) external;
}
