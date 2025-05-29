// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ClankerDeployer} from "./utils/ClankerDeployer.sol";
import {OwnerAdmins} from "./utils/OwnerAdmins.sol";

import {IClanker} from "./interfaces/IClanker.sol";
import {IClankerExtension} from "./interfaces/IClankerExtension.sol";
import {IClankerHook} from "./interfaces/IClankerHook.sol";
import {IClankerLpLocker} from "./interfaces/IClankerLpLocker.sol";
import {IClankerMevModule} from "./interfaces/IClankerMevModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Clanker Token Launcher
contract Clanker is OwnerAdmins, ReentrancyGuard, IClanker {
    string constant version = "4";

    uint256 public constant TOKEN_SUPPLY = 100_000_000_000e18; // 100b with 18 decimals
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_EXTENSIONS = 10;
    uint16 public constant MAX_EXTENSION_BPS = 9000;

    // if true, the factory will not allow supplied token deployments
    bool public deprecated;

    IClankerLpLocker locker;
    // reciever of the fees from the factory
    address public teamFeeRecipient;
    mapping(address token => DeploymentInfo deploymentInfo) public deploymentInfoForToken;

    // enabled factory modules
    mapping(address hook => bool enabled) enabledHooks;
    mapping(address extension => bool enabled) enabledExtensions;
    mapping(address mevModule => bool enabled) enabledMevModules;

    constructor(address owner_) OwnerAdmins(owner_) {
        // only non-originating tokens deployments are enabled
        // before initialization
        deprecated = true;
    }

    function initialize(address locker_, address teamFeeRecipient_) external onlyOwner {
        if (address(locker) != address(0)) revert AlreadyInitialized();

        // set the locker
        locker = IClankerLpLocker(locker_);

        // set the fee recipient
        teamFeeRecipient = teamFeeRecipient_;

        // enable deployments
        deprecated = false;
    }

    function setDeprecated(bool deprecated_) external onlyOwner {
        deprecated = deprecated_;
        emit SetDeprecated(deprecated_);
    }

    function setTeamFeeRecipient(address teamFeeRecipient_) external onlyOwner {
        address oldTeamFeeRecipient = teamFeeRecipient;
        teamFeeRecipient = teamFeeRecipient_;
        emit SetTeamFeeRecipient(oldTeamFeeRecipient, teamFeeRecipient_);
    }

    function claimTeamFees(address token) external onlyOwnerOrAdmin {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(teamFeeRecipient, balance);
        emit ClaimTeamFees(token, teamFeeRecipient, balance);
    }

    function setHook(address hook, bool enabled) external onlyOwnerOrAdmin {
        // check that the hook supports the IClankerHook interface
        if (!IClankerHook(hook).supportsInterface(type(IClankerHook).interfaceId)) {
            revert InvalidHook();
        }

        enabledHooks[hook] = enabled;

        emit SetHook(hook, enabled);
    }

    function setMevModule(address mevModule, bool enabled) external onlyOwnerOrAdmin {
        // check that the mev module supports the IClankerMevModule interface
        if (!IClankerMevModule(mevModule).supportsInterface(type(IClankerMevModule).interfaceId)) {
            revert InvalidMevModule();
        }

        enabledMevModules[mevModule] = enabled;

        emit SetMevModule(mevModule, enabled);
    }

    // enable a extension contract for use, note the extension may implement its own access control
    function setExtension(address extension, bool enabled) external onlyOwnerOrAdmin {
        // check that the extension contract supports the IClankerExtension interface
        if (!IClankerExtension(extension).supportsInterface(type(IClankerExtension).interfaceId)) {
            revert InvalidExtension();
        }

        enabledExtensions[extension] = enabled;

        emit SetExtension(extension, enabled);
    }

    // deploy a token on a non-originating chain with 0 supply,
    // this can be used to bridge tokens between superchains.
    function deployTokenZeroSupply(TokenConfig memory tokenConfig)
        external
        returns (address tokenAddress)
    {
        if (block.chainid == tokenConfig.originatingChainId) revert OnlyNonOriginatingChains();
        tokenAddress = ClankerDeployer.deployToken(tokenConfig, TOKEN_SUPPLY);
    }

    // Deploy a token and pool with the option to vault the token and buy an initial amount
    function deployToken(DeploymentConfig memory deploymentConfig)
        public
        payable
        nonReentrant
        returns (address tokenAddress)
    {
        if (deprecated) revert Deprecated();
        if (block.chainid != deploymentConfig.tokenConfig.originatingChainId) {
            revert OnlyOriginatingChain();
        }

        // deploy the token
        tokenAddress = ClankerDeployer.deployToken(deploymentConfig.tokenConfig, TOKEN_SUPPLY);

        // figure out the supply split
        uint256 extensionsSupply = _prepareExtensions(deploymentConfig.extensionConfigs);
        uint256 poolSupply = TOKEN_SUPPLY - extensionsSupply;

        // configure the pool
        PoolKey memory poolKey = _initializePool(
            deploymentConfig.poolConfig, deploymentConfig.mevModuleConfig.mevModule, tokenAddress
        );

        // have locker mint liquidity and inform the hook of the position
        _initializeLiquidity(
            deploymentConfig.lockerConfig,
            deploymentConfig.poolConfig,
            poolKey,
            poolSupply,
            tokenAddress
        );

        // trigger the extensions
        _triggerExtensions(deploymentConfig, poolKey, tokenAddress);

        // initialize the mev module
        _initializeMevModule(deploymentConfig, poolKey);

        // add the deployment info to the deployment info for token
        address[] memory extensions = new address[](deploymentConfig.extensionConfigs.length);
        for (uint256 i = 0; i < deploymentConfig.extensionConfigs.length; i++) {
            extensions[i] = deploymentConfig.extensionConfigs[i].extension;
        }

        deploymentInfoForToken[tokenAddress] = DeploymentInfo({
            token: tokenAddress,
            hook: deploymentConfig.poolConfig.hook,
            extensions: extensions
        });

        emit TokenCreated({
            msgSender: msg.sender,
            tokenAddress: tokenAddress,
            tokenAdmin: deploymentConfig.tokenConfig.tokenAdmin,
            tokenMetadata: deploymentConfig.tokenConfig.metadata,
            tokenImage: deploymentConfig.tokenConfig.image,
            tokenName: deploymentConfig.tokenConfig.name,
            tokenSymbol: deploymentConfig.tokenConfig.symbol,
            tokenContext: deploymentConfig.tokenConfig.context,
            poolHook: deploymentConfig.poolConfig.hook,
            poolId: poolKey.toId(),
            startingTick: deploymentConfig.poolConfig.tickIfToken0IsClanker,
            pairedToken: deploymentConfig.poolConfig.pairedToken,
            mevModule: deploymentConfig.mevModuleConfig.mevModule,
            extensionsSupply: extensionsSupply,
            extensions: extensions
        });
    }

    function _initializeMevModule(DeploymentConfig memory deploymentConfig, PoolKey memory poolKey)
        internal
    {
        if (!enabledMevModules[deploymentConfig.mevModuleConfig.mevModule]) {
            revert MevModuleNotEnabled();
        }

        // initialize the mev module
        IClankerHook(deploymentConfig.poolConfig.hook).initializeMevModule(
            poolKey, deploymentConfig.mevModuleConfig.mevModuleData
        );
    }

    function _initializePool(PoolConfig memory poolConfig, address mevModule, address newToken)
        internal
        returns (PoolKey memory poolKey)
    {
        // check that the pool hook is enabled
        if (!enabledHooks[poolConfig.hook]) {
            revert HookNotEnabled();
        }

        // call into the hook to initialize the pool
        poolKey = IClankerHook(poolConfig.hook).initializePool(
            newToken,
            poolConfig.pairedToken,
            poolConfig.tickIfToken0IsClanker,
            poolConfig.tickSpacing,
            mevModule,
            poolConfig.poolData
        );
    }

    function _initializeLiquidity(
        LockerConfig memory lockerConfig,
        IClanker.PoolConfig memory poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) internal {
        // approve the liquidity locker to take the pool's token supply
        IERC20(token).approve(address(locker), poolSupply);

        // have the locker mint liquidity
        locker.placeLiquidity(lockerConfig, poolConfig, poolKey, poolSupply, token);
    }

    function _prepareExtensions(ExtensionConfig[] memory extensions)
        internal
        view
        returns (uint256 extensionSupply)
    {
        if (extensions.length == 0) {
            return 0;
        }

        // check for max number of extensions
        if (extensions.length > MAX_EXTENSIONS) {
            revert MaxExtensionsExceeded();
        }

        // determine total supply percentage earmarked for extensions
        uint256 extensionSupplyPercentage = 0;
        for (uint256 i = 0; i < extensions.length; i++) {
            extensionSupplyPercentage += extensions[i].extensionBps;
        }

        // check that the extension supply percentage is less than the max extension bps
        if (extensionSupplyPercentage > MAX_EXTENSION_BPS) {
            revert MaxExtensionBpsExceeded();
        }

        // determine expected extension eth
        uint256 expectedExtensionEth = 0;
        for (uint256 i = 0; i < extensions.length; i++) {
            expectedExtensionEth += extensions[i].msgValue;
        }

        // ensure the extension expected eth is equal to the msg.value
        if (expectedExtensionEth != msg.value) {
            revert ExtensionMsgValueMismatch();
        }

        // check that the extensions are enabled
        for (uint256 i = 0; i < extensions.length; i++) {
            if (!enabledExtensions[extensions[i].extension]) {
                revert ExtensionNotEnabled();
            }
        }

        // figure out the extension supply
        extensionSupply = extensionSupplyPercentage * TOKEN_SUPPLY / BPS;
    }

    // send the tokens to the extension contract
    function _triggerExtensions(
        DeploymentConfig memory deploymentConfig,
        PoolKey memory poolKey,
        address token
    ) internal {
        // iterate over the extensions and trigger each one
        for (uint256 i = 0; i < deploymentConfig.extensionConfigs.length; i++) {
            // determine the supply for the extension
            uint256 extensionSupply =
                deploymentConfig.extensionConfigs[i].extensionBps * TOKEN_SUPPLY / BPS;

            // approve the extension contract to spend the token
            IERC20(token).approve(deploymentConfig.extensionConfigs[i].extension, extensionSupply);

            // trigger the extension
            IClankerExtension(deploymentConfig.extensionConfigs[i].extension).receiveTokens{
                value: deploymentConfig.extensionConfigs[i].msgValue
            }(deploymentConfig, poolKey, token, extensionSupply, i);

            emit ExtensionTriggered(
                deploymentConfig.extensionConfigs[i].extension,
                extensionSupply,
                deploymentConfig.extensionConfigs[i].msgValue
            );
        }
    }
}
