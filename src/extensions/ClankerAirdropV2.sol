// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerExtension} from "../interfaces/IClankerExtension.sol";
import {IClankerAirdropV2} from "./interfaces/IClankerAirdropV2.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ClankerAirdropV2 is ReentrancyGuard, IClankerAirdropV2 {
    address public immutable factory;
    mapping(address token => AirdropV2 airdrop) public airdrops;

    uint256 public constant MIN_LOCKUP_DURATION = 1 days;
    uint256 public constant CLAIM_EXPIRATION_INTERVAL = 14 days;
    uint256 public constant ZERO_CLAIM_OVERWRITE_INTERVAL = 1 days;

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
        AirdropV2ExtensionData memory airdropData = abi.decode(
            deploymentConfig.extensionConfigs[extensionIndex].extensionData,
            (AirdropV2ExtensionData)
        );

        // check that we don't already have an airdrop for this token
        if (airdrops[token].merkleRoot != bytes32(0)) {
            revert AirdropAlreadyExists();
        }

        // ensure that the msgValue is zero
        if (deploymentConfig.extensionConfigs[extensionIndex].msgValue != 0 || msg.value != 0) {
            revert IClankerExtension.InvalidMsgValue();
        }

        // check the vault percentage is not zero
        if (deploymentConfig.extensionConfigs[extensionIndex].extensionBps == 0) {
            revert InvalidAirdropPercentage();
        }

        // check that minimum lockup duration is met
        if (airdropData.lockupDuration < MIN_LOCKUP_DURATION) {
            revert AirdropLockupDurationTooShort();
        }

        // set the lockup, vesting, and claim end times
        airdrops[token].lockupEndTime = block.timestamp + airdropData.lockupDuration;
        airdrops[token].vestingEndTime =
            block.timestamp + airdropData.lockupDuration + airdropData.vestingDuration;
        airdrops[token].adminClaimTime = block.timestamp + airdropData.lockupDuration
            + airdropData.vestingDuration + CLAIM_EXPIRATION_INTERVAL;

        // set fields
        airdrops[token].admin = airdropData.admin;
        airdrops[token].merkleRoot = airdropData.merkleRoot;
        airdrops[token].totalClaimed = 0;
        airdrops[token].totalSupply = extensionSupply;

        // pull in token
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), extensionSupply);

        emit AirdropCreated({
            admin: airdropData.admin,
            token: token,
            merkleRoot: airdropData.merkleRoot,
            supply: extensionSupply,
            lockupDuration: airdropData.lockupDuration,
            vestingDuration: airdropData.vestingDuration
        });
    }

    // update the admin of the airdrop
    function updateAdmin(address token, address newAdmin) external {
        if (msg.sender != airdrops[token].admin) revert Unauthorized();
        address oldAdmin = airdrops[token].admin;
        airdrops[token].admin = newAdmin;

        emit AirdropAdminUpdated(token, oldAdmin, newAdmin);
    }

    // update the merkle root of the airdrop by admin if the merkle root is zero or if
    // the claim overwrite interval has passed without a claim
    function updateMerkleRoot(address token, bytes32 newMerkleRoot) external {
        AirdropV2 storage airdrop = airdrops[token];

        // ensure that the msg sender is the admin
        if (msg.sender != airdrop.admin) revert Unauthorized();

        // ensure that the admin has not claimed
        if (airdrop.adminClaimed) revert AdminClaimed();

        // ensure that no claims have occurred
        if (airdrop.totalClaimed > 0) revert AirdropClaimsOccurred();

        // calculate if the zero claim overwrite interval has passed
        bool zeroClaimOverwriteIntervalPassed =
            block.timestamp > airdrop.lockupEndTime + ZERO_CLAIM_OVERWRITE_INTERVAL;

        // can change the merkle root if it is zero or if the zero claim overwrite interval has passed
        if (airdrop.merkleRoot != bytes32(0) && !zeroClaimOverwriteIntervalPassed) {
            revert UpdateMerkleRootNotAllowed();
        }

        // update the merkle root
        airdrop.merkleRoot = newMerkleRoot;

        emit AirdropMerkleRootUpdated(token, airdrop.merkleRoot, newMerkleRoot);
    }

    // admins can claim the remaining balance after the claim expiration interval
    // has been hit
    function adminClaim(address token, address recipient) external {
        AirdropV2 storage airdrop = airdrops[token];
        if (msg.sender != airdrop.admin) revert Unauthorized();
        if (block.timestamp < airdrop.adminClaimTime) revert ClaimNotEnded();
        if (airdrop.adminClaimed) revert AdminClaimed();

        // update the admin claimed flag
        airdrop.adminClaimed = true;

        // transfer the remaining balance to the recipient
        SafeERC20.safeTransfer(IERC20(token), recipient, airdrop.totalSupply - airdrop.totalClaimed);

        emit AirdropAdminClaimed(token, airdrop.totalSupply - airdrop.totalClaimed);
    }

    function claim(
        address token,
        address recipient,
        uint256 allocatedAmount,
        bytes32[] calldata proof
    ) external nonReentrant {
        AirdropV2 storage airdrop = airdrops[token];

        // check that the airdrop exists
        if (airdrop.merkleRoot == bytes32(0)) {
            revert AirdropNotCreated();
        }

        // check if the admin has claimed
        if (airdrop.adminClaimed) revert AdminClaimed();

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
                keccak256(bytes.concat(keccak256(abi.encode(recipient, allocatedAmount))))
            )
        ) {
            revert InvalidProof();
        }

        // calculate amount available to claim
        uint256 amountClaimed = airdrop.amountClaimed[recipient];
        if (amountClaimed >= allocatedAmount) {
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
        SafeERC20.safeTransfer(IERC20(token), recipient, claimableAmount);

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
        if (airdrops[token].merkleRoot == bytes32(0)) {
            revert AirdropNotCreated();
        }

        // check if the admin has claimed
        if (airdrops[token].adminClaimed) revert AdminClaimed();

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
