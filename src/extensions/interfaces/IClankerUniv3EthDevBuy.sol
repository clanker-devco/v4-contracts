// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerUniv3EthDevBuy is IClankerExtension {
    struct Univ3EthDevBuyExtensionData {
        // fee of the univ3 pool to swap on
        uint24 uniV3Fee;
        // minimum amount of token to receive from the W/ETH -> paired token swap
        uint128 pairedTokenAmountOutMinimum;
        // recipient of the tokens
        address recipient;
    }

    error Unauthorized();
    error InvalidEthDevBuyPercentage();
    error InvalidPairedTokenPoolKey();

    event EthDevBuy(
        address indexed token, address indexed user, uint256 ethAmount, uint256 tokenAmount
    );
}
