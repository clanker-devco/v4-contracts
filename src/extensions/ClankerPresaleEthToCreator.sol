// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerExtension} from "../interfaces/IClankerExtension.sol";
import {IClankerPresaleEthToCreator} from "./interfaces/IClankerPresaleEthToCreator.sol";

import {IOwnerAdmins} from "../interfaces/IOwnerAdmins.sol";
import {OwnerAdmins} from "../utils/OwnerAdmins.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Test, console} from "forge-std/Test.sol";

contract ClankerPresaleEthToCreator is ReentrancyGuard, IClankerPresaleEthToCreator, OwnerAdmins {
    uint256 public constant WITHDRAW_FEE_BPS = 100; // 1%
    uint256 public constant MAX_PRESALE_DURATION = 6 weeks;
    uint256 public constant SALT_SET_BUFFER = 1 days; // buffer for presale admin to set salt for deployment
    uint256 public constant DEPLOYMENT_BAD_BUFFER = 1 days; // buffer for deployment to be considered bad
    IClanker public immutable factory;

    uint256 private _presaleId;
    mapping(uint256 presaleId => Presale presale) public presaleState;

    // presale user buy and claim amounts
    mapping(uint256 presaleId => mapping(address user => uint256 amount)) public presaleBuys;
    mapping(uint256 presaleId => mapping(address user => uint256 amount)) public presaleClaimed;

    address public withdrawFeeRecipient;
    uint256 public withdrawFeeAccumulated;

    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert Unauthorized();
        _;
    }

    modifier presaleExists(uint256 presaleId_) {
        if (presaleState[presaleId_].maxEthGoal == 0) revert InvalidPresale();
        _;
    }

    modifier updatePresaleState(uint256 presaleId_) {
        Presale storage presale = presaleState[presaleId_];

        // update to minumum or failed if time expired if in active state
        if (presale.status == PresaleStatus.Active && presale.endTime <= block.timestamp) {
            if (presale.ethRaised >= presale.minEthGoal) {
                presale.status = PresaleStatus.SuccessfulMinimumHit;
            } else {
                presale.status = PresaleStatus.Failed;
            }
        }
        _;
    }

    constructor(address owner_, address factory_, address withdrawFeeRecipient_)
        OwnerAdmins(owner_)
    {
        factory = IClanker(factory_);
        _presaleId = 1;
        withdrawFeeRecipient = withdrawFeeRecipient_;
    }

    function getPresale(uint256 presaleId_) public view returns (Presale memory) {
        return presaleState[presaleId_];
    }

    function setWithdrawFeeRecipient(address recipient) external onlyOwner {
        withdrawFeeRecipient = recipient;
    }

    function withdrawWithdrawFee() external nonReentrant {
        uint256 amount = withdrawFeeAccumulated;
        if (amount == 0) revert NoWithdrawFeeAccumulated();
        withdrawFeeAccumulated = 0;
        (bool sent,) = payable(withdrawFeeRecipient).call{value: amount}("");
        if (!sent) revert EthTransferFailed();
    }

    function startPresale(
        IClanker.DeploymentConfig memory deploymentConfig,
        uint256 minEthGoal,
        uint256 maxEthGoal,
        uint256 presaleDuration,
        address recipient,
        uint256 lockupDuration,
        uint256 vestingDuration
    ) external onlyAdmin returns (uint256 presaleId) {
        presaleId = _presaleId++;

        // ensure presale recipient is present set
        if (recipient == address(0)) {
            revert InvalidPresaleRecipient();
        }

        // ensure presale is present the last extension in the token's deployment config
        if (
            deploymentConfig.extensionConfigs.length == 0
                || deploymentConfig.extensionConfigs[deploymentConfig.extensionConfigs.length - 1]
                    .extension != address(this)
        ) {
            revert PresaleNotLastExtension();
        }

        // ensure presale supply is not zero
        if (
            deploymentConfig.extensionConfigs[deploymentConfig.extensionConfigs.length - 1]
                .extensionBps == 0
        ) {
            revert InvalidPresaleSupply();
        }

        // ensure msg value is zero
        if (
            deploymentConfig.extensionConfigs[deploymentConfig.extensionConfigs.length - 1].msgValue
                != 0
        ) {
            revert InvalidMsgValue();
        }

        // ensure min and max eth goals are present and valid
        if (maxEthGoal == 0 || minEthGoal > maxEthGoal) {
            revert InvalidEthGoal();
        }

        // ensure time limit is present and valid
        if (presaleDuration == 0 || presaleDuration > MAX_PRESALE_DURATION) {
            revert InvalidPresaleDuration();
        }

        // set token deployment config's presale ID
        deploymentConfig.extensionConfigs[deploymentConfig.extensionConfigs.length - 1]
            .extensionData = abi.encode(presaleId);

        // note: it is recommended to simulate a call to deployToken() with the deploymentConfig
        // to ensure that the token will fail with 'NotExpectingTokenDeployment()',
        // reaching this error messages means that the deploymentConfig is valid up to the
        // point of this presale executing.
        // encode the presale id of zero into the extension data for the simulation

        presaleState[presaleId] = Presale({
            recipient: recipient,
            deploymentConfig: deploymentConfig,
            status: PresaleStatus.Active,
            minEthGoal: minEthGoal,
            maxEthGoal: maxEthGoal,
            endTime: block.timestamp + presaleDuration,
            ethRaised: 0,
            deploymentExpected: false,
            deployedToken: address(0),
            tokenSupply: 0,
            ethClaimed: false,
            lockupDuration: lockupDuration,
            vestingDuration: vestingDuration,
            lockupEndTime: 0,
            vestingEndTime: 0
        });
    }

    function endPresale(uint256 presaleId, bytes32 salt)
        external
        presaleExists(presaleId)
        updatePresaleState(presaleId)
        returns (address token)
    {
        Presale storage presale = presaleState[presaleId];

        // ensure presale is ready for deployment
        if (
            presale.status != PresaleStatus.SuccessfulMaximumHit
                && presale.status != PresaleStatus.SuccessfulMinimumHit
        ) revert PresaleNotReadyForDeployment();

        // if presale's end time has passed without a successful deployment, set the presale to failed
        //
        // presales with an invalid token deployment config can fail to deploy. we don't want
        // to fail the presale if a single bad deploy happens, as someone could force a bad deploy
        // by calling endPresale() with a salt that resolves to an already deployed token
        if (presale.endTime + DEPLOYMENT_BAD_BUFFER < block.timestamp) {
            // allow users to withdraw their eth
            presale.status = PresaleStatus.Failed;
            return address(0);
        }

        // give privelged deployers opportuninty to set the salt
        if (
            msg.sender != presale.recipient && !admins[msg.sender]
                && block.timestamp < presale.endTime + SALT_SET_BUFFER
        ) revert PresaleSaltBufferNotExpired();

        // update token deployment config with salt
        presale.deploymentConfig.tokenConfig.salt = salt;

        // update presale percentage to reflect amount of tokens that were sold
        if (presale.ethRaised != presale.maxEthGoal) {
            uint256 originalBps = uint256(
                presale.deploymentConfig.extensionConfigs[presale
                    .deploymentConfig
                    .extensionConfigs
                    .length - 1].extensionBps
            );

            uint256 newBps = (originalBps * presale.ethRaised) / presale.maxEthGoal;
            presale.deploymentConfig.extensionConfigs[presale
                .deploymentConfig
                .extensionConfigs
                .length - 1].extensionBps = uint16(newBps);
        }

        // record lockup and vesting end times
        presale.lockupEndTime = block.timestamp + presale.lockupDuration;
        presale.vestingEndTime = block.timestamp + presale.lockupDuration + presale.vestingDuration;

        // set deployment ongoing to true
        presale.deploymentExpected = true;

        // deploy token
        token = factory.deployToken(presale.deploymentConfig);
    }

    function buyIntoPresale(uint256 presaleId)
        external
        payable
        presaleExists(presaleId)
        nonReentrant
    {
        Presale storage presale = presaleState[presaleId];

        // ensure presale is active and time limit has not been reached
        if (presale.status != PresaleStatus.Active || presale.endTime <= block.timestamp) {
            revert PresaleNotActive();
        }

        // determine amount of eth to use for presale
        uint256 ethToUse = msg.value + presale.ethRaised > presale.maxEthGoal
            ? presale.maxEthGoal - presale.ethRaised
            : msg.value;

        // record a user's eth contribution
        presaleBuys[presaleId][msg.sender] += ethToUse;

        // update eth raised
        presale.ethRaised += ethToUse;

        // update presale state if max eth goal is met, do not update if min goal is met
        if (presale.ethRaised == presale.maxEthGoal) {
            presale.status = PresaleStatus.SuccessfulMaximumHit;
        }

        // refund excess eth
        if (msg.value > ethToUse) {
            // send eth to recipient
            (bool sent,) = payable(msg.sender).call{value: msg.value - ethToUse}("");
            if (!sent) revert EthTransferFailed();
        }
    }

    function withdrawFromPresale(uint256 presaleId, uint256 amount, address recipient)
        external
        presaleExists(presaleId)
        updatePresaleState(presaleId)
        nonReentrant
    {
        Presale storage presale = presaleState[presaleId];

        // ensure presale is ongoing or failed
        if (
            presale.status == PresaleStatus.SuccessfulMaximumHit
                || presale.status == PresaleStatus.SuccessfulMinimumHit
                || presale.status == PresaleStatus.Claimable
        ) revert PresaleSuccessful();

        // ensure user has a balance in the presale
        if (presaleBuys[presaleId][msg.sender] < amount) revert InsufficientBalance();

        // update user's balance
        presaleBuys[presaleId][msg.sender] -= amount;

        // update eth raised
        presale.ethRaised -= amount;

        // determine fee
        uint256 fee;
        if (presale.status == PresaleStatus.Failed) {
            fee = 0;
        } else {
            fee = (amount * WITHDRAW_FEE_BPS) / 10_000;
        }
        uint256 amountAfterFee = amount - fee;

        // accumulate fee
        if (fee > 0) {
            withdrawFeeAccumulated += fee;
        }

        // send eth to recipient
        (bool sent,) = payable(recipient).call{value: amountAfterFee}("");
        if (!sent) revert EthTransferFailed();
    }

    function claimTokens(uint256 presaleId) external presaleExists(presaleId) {
        Presale storage presale = presaleState[presaleId];

        // ensure presale is claimable
        if (presale.status != PresaleStatus.Claimable) revert PresaleNotClaimable();

        // ensure lockup period has passed
        if (block.timestamp < presale.lockupEndTime) revert PresaleLockupNotPassed();

        // determine amount of tokens to send to user
        uint256 ethBuyInAmount = _getAmountClaimable(
            presaleId,
            msg.sender,
            presale.lockupEndTime,
            presale.vestingEndTime,
            presale.vestingDuration
        );

        // update user's claimed amount
        presaleClaimed[presaleId][msg.sender] += ethBuyInAmount;

        // determine token amount to send to user
        uint256 tokenAmount = presale.tokenSupply * ethBuyInAmount / presale.ethRaised;
        if (tokenAmount == 0) revert NoTokensToClaim();

        // send tokens to user
        IERC20(presale.deployedToken).transfer(msg.sender, tokenAmount);
    }

    // helper function to determine amount of tokens available to claim
    function amountAvailableToClaim(uint256 presaleId, address user)
        external
        view
        presaleExists(presaleId)
        returns (uint256)
    {
        Presale memory presale = presaleState[presaleId];

        if (presale.status != PresaleStatus.Claimable) return 0;
        if (block.timestamp < presale.lockupEndTime) return 0;

        uint256 ethBuyInAmount = _getAmountClaimable(
            presaleId, user, presale.lockupEndTime, presale.vestingEndTime, presale.vestingDuration
        );
        return presale.tokenSupply * ethBuyInAmount / presale.ethRaised;
    }

    function _getAmountClaimable(
        uint256 presaleId,
        address user,
        uint256 lockupEndTime,
        uint256 vestingEndTime,
        uint256 vestingDuration
    ) internal view returns (uint256) {
        // determine amount of tokens to send to user
        uint256 ethBuyInAmount;
        if (block.timestamp >= vestingEndTime) {
            // if vesting period has not passed, send rest of tokens
            ethBuyInAmount = presaleBuys[presaleId][user] - presaleClaimed[presaleId][user];
        } else {
            // if vesting period has not passed, send vested portion of tokens minus what
            // has already been claimed
            ethBuyInAmount =
                presaleBuys[presaleId][user] * (block.timestamp - lockupEndTime) / vestingDuration;
            ethBuyInAmount = ethBuyInAmount - presaleClaimed[presaleId][user];
        }

        return ethBuyInAmount;
    }

    function claimEth(uint256 presaleId, address recipient) external presaleExists(presaleId) {
        Presale storage presale = presaleState[presaleId];

        // if not presale recipient, revert
        if (msg.sender != presale.recipient) revert Unauthorized();

        // if eth has already been claimed, revert
        if (presale.ethClaimed) revert PresaleAlreadyClaimed();
        presale.ethClaimed = true;

        // ensure presale is claimable
        if (presale.status != PresaleStatus.Claimable) revert PresaleNotClaimable();

        // determine eth amount to send
        uint256 ethAmount = presale.ethRaised;

        // send eth to recipient
        (bool sent,) = payable(recipient).call{value: ethAmount}("");
        if (!sent) revert EthTransferFailed();
    }

    function receiveTokens(
        IClanker.DeploymentConfig calldata deploymentConfig,
        PoolKey memory,
        address token,
        uint256 extensionSupply,
        uint256 extensionIndex
    ) external payable nonReentrant onlyFactory {
        uint256 presaleId =
            abi.decode(deploymentConfig.extensionConfigs[extensionIndex].extensionData, (uint256));
        Presale storage presale = presaleState[presaleId];

        // ensure that the msgValue is zero
        if (deploymentConfig.extensionConfigs[extensionIndex].msgValue != 0 || msg.value != 0) {
            revert IClankerExtension.InvalidMsgValue();
        }

        // ensure token deployment is ongoing
        if (!presale.deploymentExpected) revert NotExpectingTokenDeployment();
        presale.deploymentExpected = false;

        // pull in token supply
        IERC20(token).transferFrom(msg.sender, address(this), extensionSupply);

        // update deployed token
        presale.deployedToken = token;

        // record token supply
        presale.tokenSupply = extensionSupply;

        // update presale state to claimable
        presale.status = PresaleStatus.Claimable;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerExtension).interfaceId;
    }
}
