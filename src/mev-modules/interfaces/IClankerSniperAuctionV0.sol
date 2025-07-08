// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerMevModule} from "../../interfaces/IClankerMevModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IClankerSniperAuctionV0 is IClankerMevModule {
    error PoolAlreadyInitialized();
    error GasSignalNegative();
    error NotAuctionBlock();

    event AuctionInitialized(
        PoolId indexed poolId, uint256 gasPeg, uint256 indexed auctionBlock, uint256 round
    );
    event AuctionWon(
        PoolId indexed poolId, address indexed payee, uint256 paymentAmount, uint256 round
    );
    event AuctionReset(
        PoolId indexed poolId, uint256 gasPeg, uint256 indexed auctionBlock, uint256 round
    );
    event AuctionExpired(PoolId indexed poolId, uint256 round);
    event AuctionEnded(PoolId indexed poolId);
    event AuctionRewardsTransferred(
        PoolId indexed poolId, uint256 lpPayment, uint256 factoryPayment
    );
    event SetBlocksBetweenDeploymentAndFirstAuction(
        uint256 oldBlocksBetweenDeploymentAndFirstAuction,
        uint256 newBlocksBetweenDeploymentAndFirstAuction
    );
    event SetBlocksBetweenAuction(uint256 oldBlocksBetweenAuction, uint256 newBlocksBetweenAuction);
    event SetMaxRounds(uint256 oldMaxRounds, uint256 newMaxRounds);
    event SetPaymentPerGasUnit(uint256 oldPaymentPerGasUnit, uint256 newPaymentPerGasUnit);

    function gasPeg(PoolId poolId) external view returns (uint256);
    function round(PoolId poolId) external view returns (uint256);
    function nextAuctionBlock(PoolId poolId) external view returns (uint256);

    function paymentPerGasUnit() external view returns (uint256);
    function maxRounds() external view returns (uint256);
    function blocksBetweenAuction() external view returns (uint256);
}