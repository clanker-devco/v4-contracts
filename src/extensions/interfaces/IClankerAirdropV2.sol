// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";

interface IClankerAirdropV2 is IClankerExtension {
    struct AirdropV2ExtensionData {
        address admin;
        bytes32 merkleRoot;
        uint256 lockupDuration;
        uint256 vestingDuration;
    }

    struct AirdropV2 {
        address admin; // admin of the airdrop
        bytes32 merkleRoot; // merkle root of the airdrop
        uint256 totalSupply; // total supply of the airdrop
        uint256 totalClaimed; // total amount claimed so far
        uint256 lockupEndTime; // when the lockup period ends
        uint256 vestingEndTime; // when the vesting period ends
        uint256 adminClaimTime; // when the owner can claim the remaining balance
        bool adminClaimed; // if the admin has claimed the remaining balance
        mapping(address => uint256) amountClaimed; // amount claimed by each recipient so far
    }

    error InvalidAirdropPercentage();
    error Unauthorized();
    error InvalidProof();
    error TotalMaxClaimed();
    error UserMaxClaimed();
    error ZeroClaim();
    error ZeroToClaim();
    error AirdropNotUnlocked();
    error AirdropAlreadyExists();
    error AirdropLockupDurationTooShort();
    error AirdropNotCreated();
    error AirdropClaimsOccurred();
    error UpdateMerkleRootNotAllowed();
    error AdminClaimed();
    error ClaimNotEnded();

    event AirdropMerkleRootUpdated(
        address indexed token, bytes32 oldMerkleRoot, bytes32 newMerkleRoot
    );

    event AirdropCreated(
        address indexed token,
        address indexed admin,
        bytes32 merkleRoot,
        uint256 supply,
        uint256 lockupDuration,
        uint256 vestingDuration
    );
    event AirdropClaimed(
        address indexed token,
        address indexed user,
        uint256 totalUserAmountClaimed,
        uint256 userAmountStillLocked
    );
    event AirdropAdminUpdated(
        address indexed token, address indexed oldAdmin, address indexed newAdmin
    );
    event AirdropAdminClaimed(address indexed token, uint256 amount);

    function claim(
        address token,
        address recipient,
        uint256 allocatedAmount,
        bytes32[] calldata proof
    ) external;

    function amountAvailableToClaim(address token, address recipient, uint256 allocatedAmount)
        external
        view
        returns (uint256);
}
