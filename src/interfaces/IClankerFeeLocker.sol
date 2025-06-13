// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerFeeLocker {
    error NoFeesToClaim();
    error Unauthorized();

    event StoreTokens(
        address indexed sender,
        address indexed feeOwner,
        address indexed token,
        uint256 balance,
        uint256 amount
    );
    event ClaimTokensPermissioned(
        address indexed feeOwner, address indexed token, address recipient, uint256 amountClaimed
    );
    event ClaimTokens(address indexed feeOwner, address indexed token, uint256 amountClaimed);
    event AddDepositor(address indexed depositor);

    function storeFees(address feeOwner, address token, uint256 amount) external;

    function claim(address feeOwner, address token) external;

    function addDepositor(address depositor) external;

    function availableFees(address feeOwner, address token) external view returns (uint256);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}
