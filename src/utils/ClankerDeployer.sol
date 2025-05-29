// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ClankerToken} from "../ClankerToken.sol";
import {IClanker} from "../interfaces/IClanker.sol";

/// @notice Clanker Token Launcher
library ClankerDeployer {
    function deployToken(IClanker.TokenConfig memory tokenConfig, uint256 supply)
        external
        returns (address tokenAddress)
    {
        ClankerToken token = new ClankerToken{
            salt: keccak256(abi.encode(tokenConfig.tokenAdmin, tokenConfig.salt))
        }(
            tokenConfig.name,
            tokenConfig.symbol,
            supply,
            tokenConfig.tokenAdmin,
            tokenConfig.image,
            tokenConfig.metadata,
            tokenConfig.context,
            tokenConfig.originatingChainId
        );
        tokenAddress = address(token);
    }
}
