// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "./IClanker.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerHook {
    error ETHPoolNotAllowed();
    error OnlyFactory();
    error UnsupportedInitializePath();
    error PastCreationTimestamp();
    error MevModuleEnabled();
    error WethCannotBeClanker();

    event PoolCreatedOpen(
        address indexed pairedToken,
        address indexed clanker,
        PoolId poolId,
        int24 tickIfToken0IsClanker,
        int24 tickSpacing
    );

    event PoolCreatedFactory(
        address indexed pairedToken,
        address indexed clanker,
        PoolId poolId,
        int24 tickIfToken0IsClanker,
        int24 tickSpacing,
        address mevModule
    );

    // note: is not emitted when a mev module expires
    event MevModuleDisabled(PoolId);
    event ClaimProtocolFees(address indexed token, uint256 amount);

    // initialize a pool on the hook for a token
    function initializePool(
        address clanker,
        address pairedToken,
        int24 tickIfToken0IsClanker,
        int24 tickSpacing,
        address mevModule,
        bytes calldata poolData
    ) external returns (PoolKey memory);

    // initialize a pool not via the factory
    function initializePoolOpen(
        address clanker,
        address pairedToken,
        int24 tickIfToken0IsClanker,
        int24 tickSpacing,
        bytes calldata poolData
    ) external returns (PoolKey memory);

    // turn a pool's mev module on if it exists
    function initializeMevModule(PoolKey calldata poolKey, bytes calldata mevModuleData) external;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
