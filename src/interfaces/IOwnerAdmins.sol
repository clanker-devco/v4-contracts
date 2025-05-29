// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOwnerAdmins {
    error Unauthorized();

    event SetAdmin(address indexed admin, bool enabled);

    function setAdmin(address admin, bool isAdmin) external;
}
