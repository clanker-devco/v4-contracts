// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOwnerAdmins} from "../../interfaces/IOwnerAdmins.sol";

interface IClankerPoolExtensionAllowlist is IOwnerAdmins {
    event SetPoolExtension(address extension, bool allowed);

    function setPoolExtension(address extension, bool allowed) external;

    function enabledExtensions(address extension) external view returns (bool enabled);
}
