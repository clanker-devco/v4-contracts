// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "./interfaces/IClanker.sol";
import {IClankerFeeLocker} from "./interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "./interfaces/IClankerLpLocker.sol";
import {IClankerLpLockerMultiple} from "./interfaces/IClankerLpLockerMultiple.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

contract ClankerLpLockerMultiple is IClankerLpLockerMultiple, ReentrancyGuard, Ownable {
    using TickMath for int24;

    string public constant version = "1";

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_REWARD_PARTICIPANTS = 7;
    uint256 public constant MAX_LP_POSITIONS = 7;

    IPositionManager public immutable positionManager;
    IPermit2 public immutable permit2;
    IClankerFeeLocker public immutable feeLocker;
    address public immutable factory;

    mapping(address token => TokenRewardInfo tokenRewardInfo) public tokenRewards;

    constructor(
        address owner_,
        address factory_, // Address of the clanker factory
        address feeLocker_,
        address positionManager_, // Address of the position manager
        address permit2_ // address of the permit2 contract
    ) Ownable(owner_) {
        factory = factory_;
        feeLocker = IClankerFeeLocker(feeLocker_);
        positionManager = IPositionManager(positionManager_);
        permit2 = IPermit2(permit2_);
    }

    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert Unauthorized();
        }
        _;
    }

    function placeLiquidity(
        IClanker.LockerConfig memory lockerConfig,
        IClanker.PoolConfig memory poolConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) external onlyFactory nonReentrant returns (uint256 positionId) {
        // ensure that we don't already have a reward for this token
        if (tokenRewards[token].positionId != 0) {
            revert TokenAlreadyHasRewards();
        }

        // create the reward info
        TokenRewardInfo memory tokenRewardInfo = TokenRewardInfo({
            token: token,
            poolKey: poolKey,
            positionId: 0, // set below
            numPositions: lockerConfig.tickLower.length,
            rewardBps: lockerConfig.rewardBps,
            rewardAdmins: lockerConfig.rewardAdmins,
            rewardRecipients: lockerConfig.rewardRecipients
        });

        // check that all arrays are the same length
        if (
            tokenRewardInfo.rewardBps.length != tokenRewardInfo.rewardAdmins.length
                || tokenRewardInfo.rewardBps.length != tokenRewardInfo.rewardRecipients.length
        ) {
            revert MismatchedRewardArrays();
        }

        // check that the number of reward participants is not greater than the max
        if (tokenRewardInfo.rewardBps.length > MAX_REWARD_PARTICIPANTS) {
            revert TooManyRewardParticipants();
        }

        // check that there is at least one reward
        if (tokenRewardInfo.rewardBps.length == 0) {
            revert NoRewardRecipients();
        }

        // check that the reward amounts add up to 10000
        uint16 totalRewards = 0;
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            totalRewards += tokenRewardInfo.rewardBps[i];
            if (tokenRewardInfo.rewardBps[i] == 0) {
                revert ZeroRewardAmount();
            }
        }
        if (totalRewards != BASIS_POINTS) {
            revert InvalidRewardBps();
        }

        // check that no address is the zero address
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            if (
                tokenRewardInfo.rewardAdmins[i] == address(0)
                    || tokenRewardInfo.rewardRecipients[i] == address(0)
            ) {
                revert ZeroRewardAddress();
            }
        }

        // pull in the token and mint liquidity
        IERC20(token).transferFrom(msg.sender, address(this), poolSupply);

        positionId = _mintLiquidity(poolConfig, lockerConfig, poolKey, poolSupply, token);

        // store the reward info
        tokenRewardInfo.positionId = positionId;
        tokenRewards[token] = tokenRewardInfo;

        emit TokenRewardAdded({
            token: tokenRewardInfo.token,
            poolKey: tokenRewardInfo.poolKey,
            positionId: tokenRewardInfo.positionId,
            numPositions: tokenRewardInfo.numPositions,
            rewardBps: tokenRewardInfo.rewardBps,
            rewardAdmins: tokenRewardInfo.rewardAdmins,
            rewardRecipients: tokenRewardInfo.rewardRecipients,
            tickLower: lockerConfig.tickLower,
            tickUpper: lockerConfig.tickUpper,
            positionBps: lockerConfig.positionBps
        });
    }

    function _mintLiquidity(
        IClanker.PoolConfig memory poolConfig,
        IClanker.LockerConfig memory lockerConfig,
        PoolKey memory poolKey,
        uint256 poolSupply,
        address token
    ) internal returns (uint256 positionId) {
        // check that all position infos are the same length
        if (
            lockerConfig.tickLower.length != lockerConfig.tickUpper.length
                || lockerConfig.tickLower.length != lockerConfig.positionBps.length
        ) {
            revert MismatchedPositionInfos();
        }

        // ensure that there is at least one position
        if (lockerConfig.tickLower.length == 0) {
            revert NoPositions();
        }

        // ensure that the max number of positions is not exceeded
        if (lockerConfig.tickLower.length > MAX_LP_POSITIONS) {
            revert TooManyPositions();
        }

        // make sure the locker position config is valid
        uint256 positionBpsTotal = 0;
        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            if (lockerConfig.tickLower[i] > lockerConfig.tickUpper[i]) {
                revert TicksBackwards();
            }
            if (
                lockerConfig.tickLower[i] < TickMath.MIN_TICK
                    || lockerConfig.tickUpper[i] > TickMath.MAX_TICK
            ) {
                revert TicksOutOfTickBounds();
            }
            if (
                lockerConfig.tickLower[i] % poolConfig.tickSpacing != 0
                    || lockerConfig.tickUpper[i] % poolConfig.tickSpacing != 0
            ) {
                revert TicksNotMultipleOfTickSpacing();
            }
            if (lockerConfig.tickLower[i] < poolConfig.tickIfToken0IsClanker) {
                revert TickRangeLowerThanStartingTick();
            }

            positionBpsTotal += lockerConfig.positionBps[i];
        }
        if (positionBpsTotal != BASIS_POINTS) {
            revert InvalidPositionBps();
        }

        bool token0IsClanker = token < poolConfig.pairedToken;

        // encode actions
        bytes[] memory params = new bytes[](lockerConfig.tickLower.length + 1);
        bytes memory actions;

        int24 startingTick =
            token0IsClanker ? lockerConfig.tickLower[0] : -lockerConfig.tickLower[0];

        for (uint256 i = 0; i < lockerConfig.tickLower.length; i++) {
            // add mint action
            actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));

            // determine token amount for this position
            uint256 tokenAmount = poolSupply * lockerConfig.positionBps[i] / BASIS_POINTS;
            uint256 amount0 = token0IsClanker ? tokenAmount : 0;
            uint256 amount1 = token0IsClanker ? 0 : tokenAmount;

            // determine tick bounds for this position
            int24 tickLower_ =
                token0IsClanker ? lockerConfig.tickLower[i] : -lockerConfig.tickLower[i];
            int24 tickUpper_ =
                token0IsClanker ? lockerConfig.tickUpper[i] : -lockerConfig.tickUpper[i];
            int24 tickLower = token0IsClanker ? tickLower_ : tickUpper_;
            int24 tickUpper = token0IsClanker ? tickUpper_ : tickLower_;
            uint160 lowerSqrtPrice = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 upperSqrtPrice = TickMath.getSqrtPriceAtTick(tickUpper);

            // determine liquidity amount
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                startingTick.getSqrtPriceAtTick(), lowerSqrtPrice, upperSqrtPrice, amount0, amount1
            );

            params[i] = abi.encode(
                poolKey,
                tickLower, // tick lower
                tickUpper, // tick upper
                liquidity, // liquidity
                amount0, // amount0Max
                amount1, // amount1Max
                address(this), // recipient of position
                abi.encode(address(this))
            );
        }

        // add settle action
        actions = abi.encodePacked(actions, uint8(Actions.SETTLE_PAIR));
        params[lockerConfig.tickLower.length] = abi.encode(poolKey.currency0, poolKey.currency1);

        // approvals
        {
            IERC20(token).approve(address(permit2), poolSupply);
            permit2.approve(
                token, address(positionManager), uint160(poolSupply), uint48(block.timestamp)
            );
        }

        // grab position id we're about to mint
        positionId = positionManager.nextTokenId();
        // add liquidity
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    // collect rewards while pool is unlocked (e.g. in an afterSwap hook)
    function collectRewardsWithoutUnlock(address token) external nonReentrant {
        _collectRewards(token, true);
    }

    // collect rewards while pool is locked
    function collectRewards(address token) external nonReentrant {
        _collectRewards(token, false);
    }

    // Collect rewards for a token
    function _collectRewards(address token, bool withoutUnlock) internal {
        // get the reward info
        TokenRewardInfo memory tokenRewardInfo = tokenRewards[token];

        // collect the rewards
        (uint256 amount0, uint256 amount1) = _bringFeesIntoContract(
            tokenRewardInfo.poolKey,
            tokenRewardInfo.positionId,
            tokenRewardInfo.numPositions,
            withoutUnlock
        );

        IERC20 rewardToken0 = IERC20(Currency.unwrap(tokenRewardInfo.poolKey.currency0));
        IERC20 rewardToken1 = IERC20(Currency.unwrap(tokenRewardInfo.poolKey.currency1));

        // determine reward distribution
        uint256[] memory rewards0 = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256[] memory rewards1 = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256 reward0Total = 0;
        uint256 reward1Total = 0;

        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length - 1; i++) {
            rewards0[i] = uint256(tokenRewardInfo.rewardBps[i]) * amount0 / BASIS_POINTS;
            rewards1[i] = uint256(tokenRewardInfo.rewardBps[i]) * amount1 / BASIS_POINTS;
            reward0Total += rewards0[i];
            reward1Total += rewards1[i];
        }
        rewards0[tokenRewardInfo.rewardBps.length - 1] = amount0 - reward0Total;
        rewards1[tokenRewardInfo.rewardBps.length - 1] = amount1 - reward1Total;

        // distribute the rewards
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            rewardToken0.approve(address(feeLocker), rewards0[i]);
            rewardToken1.approve(address(feeLocker), rewards1[i]);
            feeLocker.storeFees(
                tokenRewardInfo.rewardRecipients[i], address(rewardToken0), rewards0[i]
            );
            feeLocker.storeFees(
                tokenRewardInfo.rewardRecipients[i], address(rewardToken1), rewards1[i]
            );
        }

        // emit the claim event
        emit ClaimedRewards(tokenRewardInfo.token, amount0, amount1, rewards0, rewards1);
    }

    function _bringFeesIntoContract(
        PoolKey memory poolKey,
        uint256 positionId,
        uint256 numPositions,
        bool withoutUnlock
    ) internal returns (uint256 amount0, uint256 amount1) {
        bytes memory actions;
        bytes[] memory params = new bytes[](numPositions + 1);

        for (uint256 i = 0; i < numPositions; i++) {
            actions = abi.encodePacked(actions, uint8(Actions.DECREASE_LIQUIDITY));
            /// @dev collecting fees is achieved with liquidity=0, the second parameter
            params[i] = abi.encode(positionId + i, 0, 0, 0, abi.encode());
        }

        Currency currency0 = poolKey.currency0;
        Currency currency1 = poolKey.currency1;
        actions = abi.encodePacked(actions, uint8(Actions.TAKE_PAIR));
        params[numPositions] = abi.encode(currency0, currency1, address(this));

        uint256 balance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // when claiming from the hook, we need to call modifyLiquiditiesWithoutUnlock since
        // the pool will be in an unlocked state
        if (withoutUnlock) {
            positionManager.modifyLiquiditiesWithoutUnlock(actions, params);
        } else {
            positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);
        }

        uint256 balance0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balance1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        return (balance0After - balance0Before, balance1After - balance1Before);
    }

    // Replace the reward recipient
    function updateRewardRecipient(address token, uint256 rewardIndex, address newRecipient)
        external
    {
        TokenRewardInfo storage tokenRewardInfo = tokenRewards[token];

        // Only admin can replace the reward recipient
        if (msg.sender != tokenRewardInfo.rewardAdmins[rewardIndex]) {
            revert Unauthorized();
        }

        // Add the new recipient
        address oldRecipient = tokenRewardInfo.rewardRecipients[rewardIndex];
        tokenRewardInfo.rewardRecipients[rewardIndex] = newRecipient;

        emit RewardRecipientUpdated(token, rewardIndex, oldRecipient, newRecipient);
    }

    // Replace the reward admin
    function updateRewardAdmin(address token, uint256 rewardIndex, address newAdmin) external {
        TokenRewardInfo storage tokenRewardInfo = tokenRewards[token];

        // Only admin can replace the reward recipient
        if (msg.sender != tokenRewardInfo.rewardAdmins[rewardIndex]) {
            revert Unauthorized();
        }

        // Add the new recipient
        address oldAdmin = tokenRewardInfo.rewardAdmins[rewardIndex];
        tokenRewardInfo.rewardAdmins[rewardIndex] = newAdmin;

        emit RewardAdminUpdated(token, rewardIndex, oldAdmin, newAdmin);
    }

    // Enable contract to receive LP Tokens
    function onERC721Received(address, address from, uint256 id, bytes calldata)
        external
        returns (bytes4)
    {
        // Only Clanker Factory can send NFTs here
        if (from != factory) {
            revert Unauthorized();
        }

        emit Received(from, id);
        return IERC721Receiver.onERC721Received.selector;
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address token, address recipient) public onlyOwner {
        IERC20 token_ = IERC20(token);
        token_.transfer(recipient, token_.balanceOf(address(this)));
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IClankerLpLocker).interfaceId;
    }
}
