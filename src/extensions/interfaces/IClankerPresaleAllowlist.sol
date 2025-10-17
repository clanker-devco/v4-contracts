// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IClankerPresaleAllowlist {
    error Unauthorized();

    // called once per presale to pass in allowlist specific data
    function initialize(uint256 presaleId, address presaleOwner, bytes calldata initializationData)
        external;

    // get the allowed amount for a buyer
    function getAllowedAmountForBuyer(uint256 presaleId, address buyer, bytes calldata proof)
        external
        view
        returns (uint256);
}