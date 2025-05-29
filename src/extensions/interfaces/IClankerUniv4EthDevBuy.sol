// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerUniv4EthDevBuy is IClankerExtension {
    struct Univ4EthDevBuyExtensionData {
        // pool key to swap from W/ETH to paired token if the paired token is not WETH
        PoolKey pairedTokenPoolKey;
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
