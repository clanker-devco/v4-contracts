// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "./IClanker.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerExtension is IERC165 {
    // error when the msgValue is not zero when it is expected to be zero
    error InvalidMsgValue();

    // take extension's token supply from the factory and perform allocation logic
    function receiveTokens(
        IClanker.DeploymentConfig calldata deploymentConfig,
        PoolKey memory poolKey,
        address token,
        uint256 extensionSupply,
        uint256 extensionIndex
    ) external payable;
}
