// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerExtension} from "../../interfaces/IClankerExtension.sol";

interface IClankerUniv4SwapEthv3DevBuy is IClankerExtension {
    struct Univ4SwapEthv3DevBuyExtensionData {
        // pool fee when swapping from W/ETH to paired token if the paired token is not WETH
        uint24 pairedTokenPoolFee;
        // minimum amount of token to receive from the W/ETH -> paired token swap
        uint128 pairedTokenAmountOutMinimum;
        // recipient of the tokens
        address recipient;
    }

    error Unauthorized();
    error InvalidEthDevBuyPercentage();

    event EthDevBuy(
        address indexed token, address indexed user, uint256 ethAmount, uint256 tokenAmount
    );
}
