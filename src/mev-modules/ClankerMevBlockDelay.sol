// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerMevModule} from "../interfaces/IClankerMevModule.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract ClankerMevBlockDelay is IClankerMevModule {
    mapping(PoolId => uint256) public poolUnlockTime;

    uint256 public blockDelay;

    constructor(uint256 _blockDelay) {
        blockDelay = _blockDelay;
    }

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    // initialize the mev module
    function initialize(PoolKey calldata poolKey, bytes calldata) external onlyHook(poolKey) {
        // set the pool unlock time to two blocks in the future
        poolUnlockTime[poolKey.toId()] = block.number + blockDelay;
    }

    // before a swap, call the mev module
    function beforeSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        bool,
        bytes calldata
    ) external onlyHook(poolKey) returns (bool disableMevModule) {
        // check if the pool is locked
        if (block.number < poolUnlockTime[poolKey.toId()]) {
            revert PoolLocked();
        }

        // pool should be unlocked now
        return true;
    }

    // implements the IClankerMevModule interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerMevModule).interfaceId;
    }
}
