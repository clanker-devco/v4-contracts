// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../../interfaces/IClanker.sol";
import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";

interface IClankerPresaleEthToCreator is IClankerExtension {
    struct Presale {
        IClanker.DeploymentConfig deploymentConfig; // token to be deployed upon successful presale
        PresaleStatus status; // current status of the presale
        // presale success configuration fields
        address recipient; // address to claim raised eth on successful presale
        uint256 minEthGoal; // minimum eth goal for successful presale, presale will fail if this goal is not met and the time limit is reached
        uint256 maxEthGoal; // maximum eth goal for successful presale, presale will end early if this goal is reached
        uint256 endTime; // timestamp when presale expires
        // presale fields
        address deployedToken; // address of the token that was deployed
        uint256 ethRaised; // total eth raised during presale
        uint256 tokenSupply; // supply of the token that was deployed to distribute to presale buyers
        // toggle flags
        bool deploymentExpected; // bool to flag to us that we are expecting a token deployment from the factory
        bool ethClaimed; // bool to flag to us that the tokens have been claimed
        // lockup and vesting fields
        uint256 lockupDuration; // duration of the lockup period
        uint256 vestingDuration; // duration of the vesting period
        uint256 lockupEndTime; // timestamp to mark when the lockup period ends
        uint256 vestingEndTime; // timestamp to mark when the vesting period ends
    }

    enum PresaleStatus {
        NotCreated,
        Active,
        SuccessfulMinimumHit,
        SuccessfulMaximumHit,
        Failed,
        Claimable
    }

    error PresaleNotLastExtension();
    error InvalidPresaleSupply();
    error InvalidPresaleDuration();
    error InvalidEthGoal();
    error InvalidPresaleRecipient();
    error InvalidTimeLimit();

    error PresaleNotActive();
    error PresaleSuccessful();
    error InsufficientBalance();
    error InvalidPresale();
    error PresaleStillActive();
    error PresaleNotReadyForDeployment();
    error PresaleFailed();
    error PresaleClaimable();
    error PresaleAlreadyClaimed();
    error PresaleSaltBufferNotExpired();
    error NoTokensToClaim();
    error NotExpectingTokenDeployment();
    error PresaleNotClaimable();
    error PresaleLockupNotPassed();
    error EthTransferFailed();
    error NoWithdrawFeeAccumulated();

    function getPresale(uint256 _presaleId) external view returns (Presale memory);
}
