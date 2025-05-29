// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOwnerAdmins} from "./IOwnerAdmins.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IClanker is IOwnerAdmins {
    struct TokenConfig {
        address tokenAdmin;
        string name;
        string symbol;
        bytes32 salt;
        string image;
        string metadata;
        string context;
        uint256 originatingChainId;
    }

    struct PoolConfig {
        address hook;
        address pairedToken;
        int24 tickIfToken0IsClanker;
        int24 tickSpacing;
        bytes poolData;
    }

    struct LockerConfig {
        // reward info
        address[] rewardAdmins;
        address[] rewardRecipients;
        uint16[] rewardBps;
        // liquidity placement info
        int24[] tickLower;
        int24[] tickUpper;
        uint16[] positionBps;
    }

    struct ExtensionConfig {
        address extension;
        uint256 msgValue;
        uint16 extensionBps;
        bytes extensionData;
    }

    struct DeploymentConfig {
        TokenConfig tokenConfig;
        PoolConfig poolConfig;
        LockerConfig lockerConfig;
        MevModuleConfig mevModuleConfig;
        ExtensionConfig[] extensionConfigs;
    }

    struct MevModuleConfig {
        address mevModule;
        bytes mevModuleData;
    }

    struct DeploymentInfo {
        address token;
        address hook;
        address[] extensions;
    }

    /// @notice When the clanker is already initialized
    error AlreadyInitialized();

    /// @notice When the factory is deprecated
    error Deprecated();
    /// @notice When the token is not found to collect rewards for
    error NotFound();

    /// @notice When the function is only valid on the originating chain
    error OnlyOriginatingChain();
    /// @notice When the function is only valid on a non-originating chain
    error OnlyNonOriginatingChains();

    /// @notice When the hook is invalid
    error InvalidHook();
    /// @notice When the locker is invalid
    error InvalidLocker();
    /// @notice When the extension contract is invalid
    error InvalidExtension();

    /// @notice When the hook is not enabled
    error HookNotEnabled();
    /// @notice When the extension contract is not enabled
    error ExtensionNotEnabled();
    /// @notice When the mev module is not enabled
    error MevModuleNotEnabled();

    /// @notice When the token is not paired to the pool
    error ExtensionMsgValueMismatch();
    /// @notice When the maximum number of extensions is exceeded
    error MaxExtensionsExceeded();
    /// @notice When the extension supply percentage is exceeded
    error MaxExtensionBpsExceeded();

    /// @notice When the mev module is invalid
    error InvalidMevModule();

    event TokenCreated(
        address msgSender,
        address indexed tokenAddress,
        address indexed tokenAdmin,
        string tokenImage,
        string tokenName,
        string tokenSymbol,
        string tokenMetadata,
        string tokenContext,
        int24 startingTick,
        address poolHook,
        PoolId poolId,
        address pairedToken,
        address mevModule,
        uint256 extensionsSupply,
        address[] extensions
    );
    event ExtensionTriggered(address extension, uint256 extensionSupply, uint256 msgValue);

    event SetDeprecated(bool deprecated);
    event SetExtension(address extension, bool enabled);
    event SetHook(address hook, bool enabled);
    event SetMevModule(address mevModule, bool enabled);

    event SetTeamFeeRecipient(address oldTeamFeeRecipient, address newTeamFeeRecipient);
    event ClaimTeamFees(address indexed token, address indexed recipient, uint256 amount);

    function deprecated() external view returns (bool);

    function deployTokenZeroSupply(TokenConfig memory tokenConfig)
        external
        returns (address tokenAddress);

    function deployToken(DeploymentConfig memory deploymentConfig)
        external
        payable
        returns (address tokenAddress);
}
