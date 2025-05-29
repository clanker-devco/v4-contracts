// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerExtension} from "../interfaces/IClankerExtension.sol";
import {IClankerAirdrop} from "./interfaces/IClankerAirdrop.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ClankerAirdrop is ReentrancyGuard, IClankerAirdrop {
    address public immutable factory;
    mapping(address token => Airdrop airdrop) public airdrops;

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    constructor(address factory_) {
        factory = factory_;
    }

    function receiveTokens(
        IClanker.DeploymentConfig calldata deploymentConfig,
        PoolKey memory,
        address token,
        uint256 extensionSupply,
        uint256 extensionIndex
    ) external payable nonReentrant onlyFactory {
        AirdropExtensionData memory airdropData = abi.decode(
            deploymentConfig.extensionConfigs[extensionIndex].extensionData, (AirdropExtensionData)
        );

        // check that we don't already have an airdrop for this token
        if (airdrops[token].merkleRoot != bytes32(0)) {
            revert AirdropAlreadyExists();
        }

        // ensure that the msgValue is zero
        if (deploymentConfig.extensionConfigs[extensionIndex].msgValue != 0 || msg.value != 0) {
            revert IClankerExtension.InvalidMsgValue();
        }

        // ensure that the merkle root is set
        if (airdropData.merkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // check the vault percentage is not zero
        if (deploymentConfig.extensionConfigs[extensionIndex].extensionBps == 0) {
            revert InvalidAirdropPercentage();
        }

        // set the lockup and vesting end times
        airdrops[token].lockupEndTime = block.timestamp + airdropData.lockupDuration;
        airdrops[token].vestingEndTime =
            block.timestamp + airdropData.lockupDuration + airdropData.vestingDuration;

        // set fields
        airdrops[token].merkleRoot = airdropData.merkleRoot;
        airdrops[token].totalClaimed = 0;
        airdrops[token].totalSupply = extensionSupply;

        // pull in token
        IERC20(token).transferFrom(msg.sender, address(this), extensionSupply);

        emit AirdropCreated(token, airdropData.merkleRoot, extensionSupply);
    }

    function claim(
        address token,
        address recipient,
        uint256 allocatedAmount,
        bytes32[] calldata proof
    ) external nonReentrant {
        Airdrop storage airdrop = airdrops[token];

        // check that the lockup period has passed
        if (block.timestamp < airdrop.lockupEndTime) {
            revert AirdropNotUnlocked();
        }

        // check that the allocated amount is not zero
        if (allocatedAmount == 0) {
            revert ZeroClaim();
        }

        // check that the max claim amount has not been exceeded
        if (airdrop.totalClaimed >= airdrop.totalSupply) {
            revert TotalMaxClaimed();
        }

        // verify proof
        if (
            !MerkleProof.verifyCalldata(
                proof,
                airdrop.merkleRoot,
                keccak256(bytes.concat(keccak256(abi.encode(recipient, token, allocatedAmount))))
            )
        ) {
            revert InvalidProof();
        }

        // calculate amount available to claim
        uint256 amountClaimed = airdrop.amountClaimed[recipient];
        if (amountClaimed == allocatedAmount) {
            revert UserMaxClaimed();
        }

        // get total available amount unlocked
        uint256 claimableAmount = _getAmountClaimable(token, allocatedAmount, amountClaimed);

        // modulate down the amount available to claim if greater than available supply
        if (airdrop.totalClaimed + claimableAmount >= airdrop.totalSupply) {
            claimableAmount = airdrop.totalSupply - airdrop.totalClaimed;
        }

        if (claimableAmount == 0) {
            revert ZeroToClaim();
        }

        // update claimed amounts
        airdrop.amountClaimed[recipient] += claimableAmount;
        airdrop.totalClaimed += claimableAmount;

        // transfer tokens
        IERC20(token).transfer(recipient, claimableAmount);

        emit AirdropClaimed(
            token,
            recipient,
            airdrop.amountClaimed[recipient],
            allocatedAmount - airdrop.amountClaimed[recipient]
        );
    }

    // helper function to surface the amount available to claim for a user,
    // assuming that there exists a proof for the allocated amount
    function amountAvailableToClaim(address token, address recipient, uint256 allocatedAmount)
        external
        view
        returns (uint256)
    {
        if (block.timestamp < airdrops[token].lockupEndTime) return 0;

        return _getAmountClaimable(token, allocatedAmount, airdrops[token].amountClaimed[recipient]);
    }

    function _getAmountClaimable(address token, uint256 allocatedAmount, uint256 totalUserClaimed)
        internal
        view
        returns (uint256)
    {
        if (block.timestamp >= airdrops[token].vestingEndTime) {
            // if the vesting period has passed, withdraw the remaining balance
            return allocatedAmount - totalUserClaimed;
        } else {
            // if the vesting period has not passed, calculate the amount to withdraw based on the
            // vesting period and how much has already been withdrawn
            uint256 totalAmountAvailable = allocatedAmount
                * (block.timestamp - airdrops[token].lockupEndTime)
                / (airdrops[token].vestingEndTime - airdrops[token].lockupEndTime);

            return totalAmountAvailable - totalUserClaimed;
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerExtension).interfaceId;
    }
}
