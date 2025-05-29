// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOwnerAdmins} from "../interfaces/IOwnerAdmins.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract OwnerAdmins is Ownable, IOwnerAdmins {
    mapping(address => bool) public admins;

    constructor(address owner_) Ownable(owner_) {}

    function setAdmin(address admin, bool enabled) external onlyOwner {
        admins[admin] = enabled;
        emit SetAdmin(admin, enabled);
    }

    modifier onlyAdmin() {
        if (!admins[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlyOwnerOrAdmin() {
        if (!admins[msg.sender] && msg.sender != owner()) revert Unauthorized();
        _;
    }
}
