// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerExtension} from "../interfaces/IClankerExtension.sol";
import {IClankerVault} from "./interfaces/IClankerVault.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract ClankerVault is ReentrancyGuard, IClankerVault {
    address public immutable factory;

    mapping(address => Allocation) public allocation;

    uint256 public constant MIN_LOCKUP_DURATION = 7 days;

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
        VaultExtensionData memory vaultData = abi.decode(
            deploymentConfig.extensionConfigs[extensionIndex].extensionData, (VaultExtensionData)
        );

        // ensure that the msgValue is zero
        if (deploymentConfig.extensionConfigs[extensionIndex].msgValue != 0 || msg.value != 0) {
            revert IClankerExtension.InvalidMsgValue();
        }

        uint256 lockupEndTime = block.timestamp + vaultData.lockupDuration;

        // check the vault percentage is not zero
        if (deploymentConfig.extensionConfigs[extensionIndex].extensionBps == 0) {
            revert InvalidVaultBps();
        }

        // check that minimum lockup duration is met
        if (vaultData.lockupDuration < MIN_LOCKUP_DURATION) {
            revert VaultLockupDurationTooShort();
        }

        // check the admin is set
        if (vaultData.admin == address(0)) {
            revert InvalidVaultAdmin();
        }

        // only one allocation per token
        if (allocation[token].lockupEndTime != 0) revert AllocationAlreadyExists();

        allocation[token] = Allocation({
            token: token,
            amountTotal: extensionSupply,
            amountClaimed: 0,
            lockupEndTime: lockupEndTime,
            vestingEndTime: lockupEndTime + vaultData.vestingDuration,
            admin: vaultData.admin
        });

        // pull in token
        if (!IERC20(token).transferFrom(msg.sender, address(this), extensionSupply)) {
            revert TransferFailed();
        }

        emit AllocationCreated({
            token: token,
            admin: vaultData.admin,
            supply: extensionSupply,
            lockupDuration: vaultData.lockupDuration,
            vestingDuration: vaultData.vestingDuration
        });
    }

    function editAllocationAdmin(address token, address newAdmin) external {
        if (msg.sender != allocation[token].admin) revert Unauthorized();
        allocation[token].admin = newAdmin;

        emit AllocationAdminUpdated(token, msg.sender, newAdmin);
    }

    function amountAvailableToClaim(address token) external view returns (uint256) {
        return _getAmountToClaim(token);
    }

    function claim(address token) external nonReentrant {
        // ensure lockup period has passed
        if (block.timestamp < allocation[token].lockupEndTime) {
            revert AllocationNotUnlocked();
        }

        uint256 amountToClaim;

        // check amount to claim
        amountToClaim = _getAmountToClaim(token);
        if (amountToClaim == 0) revert NoBalanceToClaim();

        // update the amount claimed
        allocation[token].amountClaimed += amountToClaim;

        if (!IERC20(token).transfer(allocation[token].admin, amountToClaim)) {
            revert TransferFailed();
        }

        emit AllocationClaimed(token, amountToClaim, allocation[token].amountTotal - amountToClaim);
    }

    function _getAmountToClaim(address token) internal view returns (uint256) {
        if (block.timestamp < allocation[token].lockupEndTime) {
            // still in lockup period
            return 0;
        } else if (block.timestamp >= allocation[token].vestingEndTime) {
            // if the vesting period has passed, claim the remaining balance
            return allocation[token].amountTotal - allocation[token].amountClaimed;
        } else {
            // if the vesting period has not passed, calculate the amount to claim based on the
            // vesting period and how much has already been claimed
            uint256 totalAmountAvailable = allocation[token].amountTotal
                * (block.timestamp - allocation[token].lockupEndTime)
                / (allocation[token].vestingEndTime - allocation[token].lockupEndTime);

            return totalAmountAvailable - allocation[token].amountClaimed;
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerExtension).interfaceId;
    }
}
