// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../interfaces/IClanker.sol";
import {IClankerFeeLocker} from "../interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "../interfaces/IClankerLpLocker.sol";
import {IClankerMevModule} from "../interfaces/IClankerMevModule.sol";
import {IClankerSniperAuctionV0} from "./interfaces/IClankerSniperAuctionV0.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 .--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--. 
/ .. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \
\ \/\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ \/ /
 \/ /`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'\/ / 
 / /\  ````````````````````````````````````````````````````````````````````````````````````  / /\ 
/ /\ \ ```````````````````````````````````````````````````````````````````````````````````` / /\ \
\ \/ / ```````::::::::``:::````````````:::`````::::````:::`:::````:::`::::::::::`:::::::::` \ \/ /
 \/ /  `````:+:````:+:`:+:``````````:+:`:+:```:+:+:```:+:`:+:```:+:``:+:````````:+:````:+:`  \/ / 
 / /\  ````+:+````````+:+`````````+:+```+:+``:+:+:+``+:+`+:+``+:+```+:+````````+:+````+:+``  / /\ 
/ /\ \ ```+#+````````+#+````````+#++:++#++:`+#+`+:+`+#+`+#++:++````+#++:++#```+#++:++#:```` / /\ \
\ \/ / ``+#+````````+#+````````+#+`````+#+`+#+``+#+#+#`+#+``+#+```+#+````````+#+````+#+```` \ \/ /
 \/ /  `#+#````#+#`#+#````````#+#`````#+#`#+#```#+#+#`#+#```#+#``#+#````````#+#````#+#`````  \/ / 
 / /\  `########``##########`###`````###`###````####`###````###`##########`###````###``````  / /\ 
/ /\ \ ```````````````````````````````````````````````````````````````````````````````````` / /\ \
\ \/ / ```````````````````````````````````````````````````````````````````````````````````` \ \/ /
 \/ /  ````````````````````````````````````````````````````````````````````````````````````  \/ / 
 / /\.--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--./ /\ 
/ /\ \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \/\ \
\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `' /
 `--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--' 
*/

contract ClankerSniperAuctionV0 is ReentrancyGuard, IClankerSniperAuctionV0, Ownable {
    // gas peg and block number for a pool's auction
    mapping(PoolId => uint256 gasPeg) public gasPeg;
    mapping(PoolId => uint256 nextAuctionBlock) public nextAuctionBlock;
    // round of the auction
    mapping(PoolId => uint256 round) public round;

    // block between deployment and first auction
    uint256 public blocksBetweenDeploymentAndFirstAuction;

    // blocks between recurrent auction
    uint256 public blocksBetweenAuction;

    // max rounds of auction
    uint256 public maxRounds;

    // payment amount per gas unit difference
    uint256 public paymentPerGasUnit;

    // factory's portion of the payment
    uint256 public constant FACTORY_PORTION = 2000;
    uint256 public constant BPS = 10_000;

    address public immutable weth;

    IClanker public immutable clankerFactory;
    IClankerFeeLocker public immutable feeLocker;

    constructor(address owner_, address _clankerFactory, address _feeLocker, address _weth)
        Ownable(owner_)
    {
        clankerFactory = IClanker(_clankerFactory);
        feeLocker = IClankerFeeLocker(_feeLocker);
        weth = _weth;

        blocksBetweenDeploymentAndFirstAuction = 2;
        blocksBetweenAuction = 2;
        maxRounds = 5;
        paymentPerGasUnit = 0.0001 ether;
    }

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    function setBlocksBetweenDeploymentAndFirstAuction(
        uint256 _blocksBetweenDeploymentAndFirstAuction
    ) external onlyOwner {
        uint256 oldBlocksBetweenDeploymentAndFirstAuction = blocksBetweenDeploymentAndFirstAuction;
        blocksBetweenDeploymentAndFirstAuction = _blocksBetweenDeploymentAndFirstAuction;

        emit SetBlocksBetweenDeploymentAndFirstAuction(
            oldBlocksBetweenDeploymentAndFirstAuction, blocksBetweenDeploymentAndFirstAuction
        );
    }

    function setBlocksBetweenAuction(uint256 _blocksBetweenAuction) external onlyOwner {
        uint256 oldBlocksBetweenAuction = blocksBetweenAuction;
        blocksBetweenAuction = _blocksBetweenAuction;

        emit SetBlocksBetweenAuction(oldBlocksBetweenAuction, blocksBetweenAuction);
    }

    function setPaymentPerGasUnit(uint256 _paymentPerGasUnit) external onlyOwner {
        uint256 oldPaymentPerGasUnit = paymentPerGasUnit;
        paymentPerGasUnit = _paymentPerGasUnit;

        emit SetPaymentPerGasUnit(oldPaymentPerGasUnit, paymentPerGasUnit);
    }

    function setMaxRounds(uint256 _maxRounds) external onlyOwner {
        uint256 oldMaxRounds = maxRounds;
        maxRounds = _maxRounds;

        emit SetMaxRounds(oldMaxRounds, maxRounds);
    }

    // initialize the mev module for a specific pool, called by the hook
    function initialize(PoolKey calldata poolKey, bytes calldata)
        external
        nonReentrant
        onlyHook(poolKey)
    {
        PoolId poolId = poolKey.toId();

        // check if the pool is already initialized
        if (gasPeg[poolId] != 0) {
            revert PoolAlreadyInitialized();
        }

        // get the first round's gas peg
        gasPeg[poolId] = _getBaseAuctionGasPeg(blocksBetweenDeploymentAndFirstAuction);

        // track the block number for the auction to be ran in
        nextAuctionBlock[poolId] = block.number + blocksBetweenDeploymentAndFirstAuction;

        // set the round to 1
        round[poolId] = 1;

        emit AuctionInitialized(poolId, gasPeg[poolId], block.number, round[poolId]);
    }

    function _getBaseAuctionGasPeg(uint256 _blocksBetweenAuction) internal view returns (uint256) {
        // Assuming that the sequencer is running vanilla EIP-1559, gas prices can increase
        // by max 12.5% per block if the previous block was full. To enable a clean signal
        // for the auction, we peg the starting auction's gas price to tx.base_gas *
        // (1.125 ^ (_blocksBetweenAuction))
        //
        // This ensures that the lowest gas price signal can accommodate the highest shift
        // in the gas price
        return block.basefee * (1125 ** _blocksBetweenAuction) / (1000 ** _blocksBetweenAuction);
    }

    // pull payment from the payee, the price is a multiple of tx's gas price
    // minus the gas peg
    function _pullPayment(PoolId poolId, bytes calldata auctionData)
        internal
        returns (uint256 paymentAmount)
    {
        (address payee) = abi.decode(auctionData, (address));

        // calculate the expected payment for the given gas price
        int256 gasSignal = int256(tx.gasprice) - int256(gasPeg[poolId]);

        // shouldn't be negative
        if (gasSignal < 0) {
            revert GasSignalNegative();
        }

        // calculate the expected payment for the given swap params
        paymentAmount = uint256(gasSignal) * paymentPerGasUnit;

        // pull payment from the payee
        SafeERC20.safeTransferFrom(IERC20(weth), payee, address(this), paymentAmount);

        emit AuctionWon(poolId, payee, paymentAmount, round[poolId]);
    }

    function _sendPayment(PoolKey calldata poolKey, bool clankerIsToken0, uint256 paymentAmount)
        internal
    {
        // determine factory vs lp payment split
        uint256 factoryPayment = paymentAmount * FACTORY_PORTION / BPS;
        uint256 lpPayment = paymentAmount - factoryPayment;

        // send factory's portion
        SafeERC20.safeTransfer(IERC20(weth), address(clankerFactory), factoryPayment);

        address clanker = clankerIsToken0
            ? Currency.unwrap(poolKey.currency0)
            : Currency.unwrap(poolKey.currency1);

        // grab locker address from factory
        address lpLocker = clankerFactory.tokenDeploymentInfo(clanker).locker;

        // get reward info from the locker
        IClankerLpLocker.TokenRewardInfo memory tokenRewardInfo =
            IClankerLpLocker(lpLocker).tokenRewards(clanker);

        // get the reward recipients and their splits
        uint256[] memory rewardsSplit = new uint256[](tokenRewardInfo.rewardBps.length);
        uint256 rewardTotal = 0;

        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length - 1; i++) {
            rewardsSplit[i] = tokenRewardInfo.rewardBps[i] * lpPayment / BPS;
            rewardTotal += rewardsSplit[i];
        }
        rewardsSplit[tokenRewardInfo.rewardBps.length - 1] = lpPayment - rewardTotal;

        // distribute the rewards
        for (uint256 i = 0; i < tokenRewardInfo.rewardBps.length; i++) {
            IERC20(weth).approve(address(feeLocker), rewardsSplit[i]);
            feeLocker.storeFees(tokenRewardInfo.rewardRecipients[i], weth, rewardsSplit[i]);
        }

        emit AuctionRewardsTransferred(poolKey.toId(), lpPayment, factoryPayment);
    }

    function _prepareNextRound(PoolId poolId) internal returns (bool nextRound) {
        // bump round
        round[poolId] = round[poolId] + 1;

        // check if max rounds have been reached
        if (round[poolId] > maxRounds) {
            emit AuctionEnded(poolId);
            return true;
        }

        // setup other variables for the next round
        gasPeg[poolId] = _getBaseAuctionGasPeg(blocksBetweenAuction);
        nextAuctionBlock[poolId] = block.number + blocksBetweenAuction;

        emit AuctionReset(poolId, round[poolId]);

        return false;
    }

    // the hook calls this function in it's _beforeSwap logic
    function beforeSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        bool clankerIsToken0,
        bytes calldata auctionData // expected to be address paying
    ) external nonReentrant onlyHook(poolKey) returns (bool disableMevModule) {
        // check if the auction is ready to be ran
        if (block.number < nextAuctionBlock[poolKey.toId()]) {
            // auction block not reached yet
            revert NotAuctionBlock();
        } else if (block.number > nextAuctionBlock[poolKey.toId()]) {
            // auction block passed with no winner, disable the module even if not all
            // rounds have been run and let the swap happen
            emit AuctionExpired(poolKey.toId(), round[poolKey.toId()]);
            return true;
        }

        // pull payment from the payee
        uint256 paymentAmount = _pullPayment(poolKey.toId(), auctionData);

        // send payment to fee recipients
        _sendPayment(poolKey, clankerIsToken0, paymentAmount);

        // setup auction for next round or disable if max rounds reached
        return _prepareNextRound(poolKey.toId());
    }

    // implements the IClankerMevModule interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerMevModule).interfaceId;
    }
}