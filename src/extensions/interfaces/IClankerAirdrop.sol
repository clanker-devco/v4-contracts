// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";

interface IClankerAirdrop is IClankerExtension {
    struct AirdropExtensionData {
        bytes32 merkleRoot;
        uint256 lockupDuration;
        uint256 vestingDuration;
    }

    struct Airdrop {
        bytes32 merkleRoot;
        uint256 totalSupply;
        uint256 totalClaimed;
        uint256 lockupEndTime;
        uint256 vestingEndTime;
        mapping(address => uint256) amountClaimed;
    }

    error InvalidMerkleRoot();
    error InvalidAirdropPercentage();
    error Unauthorized();
    error InvalidProof();
    error TotalMaxClaimed();
    error UserMaxClaimed();
    error ZeroClaim();
    error ZeroToClaim();
    error AirdropNotUnlocked();
    error AirdropAlreadyExists();

    event AirdropCreated(address indexed token, bytes32 merkleRoot, uint256 supply);
    event AirdropClaimed(
        address indexed token,
        address indexed user,
        uint256 totalUserAmountClaimed,
        uint256 userAmountStillLocked
    );

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
