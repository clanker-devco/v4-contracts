// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "../../interfaces/IClanker.sol";
import {IClankerFeeLocker} from "../../interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "../../interfaces/IClankerLpLocker.sol";
import {IClankerLpLockerFeeConversion} from
    "../../lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";
import {IClankerHookV2} from "../interfaces/IClankerHookV2.sol";

import {IClankerHookV2PoolExtension} from "../interfaces/IClankerHookV2PoolExtension.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {ISwapRouterV3} from "../../utils/ISwapRouterv3.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// example pool extension that takes fees generated for a fee recipient and
// swaps them for a different token
contract UniV3SwapExtension is IClankerHookV2PoolExtension, Ownable {
    error ClankerNotPairedWithTargetInputToken();
    error InvalidFirstFeeRecipient();
    error InvalidFirstFeeAdmin();
    error InvalidFirstFeePreference();
    error OnlyApprovedHooks();

    event PoolInitialized(PoolId poolId, address clanker, uint16 feeBps);
    event BuyBackRecipientSet(address previousBuyBackRecipient, address newBuyBackRecipient);
    event HookApproved(address hook);
    event SwappedBack(address inputToken, address outputToken, uint256 amountIn, uint256 amountOut);

    IClanker immutable clankerFactory;
    IClankerFeeLocker immutable feeLocker;
    ISwapRouterV3 immutable uniV3Router;
    // addresses of hooks allowed to call the afterSwap function
    mapping(address hook => bool approved) public approvedHooks;

    // univ3 pool to swap fee token for
    address public immutable inputToken;
    address public immutable outputToken;
    uint24 public immutable uniV3Fee;

    // address to receive the bought tokens
    address public buyBackRecipient;

    constructor(
        address _owner,
        address _clankerFactory,
        address _feeLocker,
        address _uniV3Router,
        address _inputToken,
        address _outputToken,
        uint24 _uniV3Fee,
        address _buyBackRecipient,
        address[] memory _approvedHooks
    ) Ownable(_owner) {
        clankerFactory = IClanker(_clankerFactory);
        feeLocker = IClankerFeeLocker(_feeLocker);
        uniV3Router = ISwapRouterV3(_uniV3Router);
        inputToken = _inputToken;
        outputToken = _outputToken;
        uniV3Fee = _uniV3Fee;
        buyBackRecipient = _buyBackRecipient;
        for (uint256 i = 0; i < _approvedHooks.length; i++) {
            approvedHooks[_approvedHooks[i]] = true;
        }
    }

    modifier onlyApprovedHooks() {
        if (!approvedHooks[msg.sender]) {
            revert OnlyApprovedHooks();
        }
        _;
    }

    // change the address that receives the bought back fees
    function setBuyBackRecipient(address _buyBackRecipient) external onlyOwner {
        address previousBuyBackRecipient = buyBackRecipient;
        buyBackRecipient = _buyBackRecipient;
        emit BuyBackRecipientSet(previousBuyBackRecipient, buyBackRecipient);
    }

    // add new hooks the the approved hooks list
    function approveHook(address _hook) external onlyOwner {
        approvedHooks[_hook] = true;
        emit HookApproved(_hook);
    }

    // initialize the user extension with passed in data, called once per pool
    function initializePreLockerSetup(PoolKey calldata, bool, bytes calldata)
        external
        onlyApprovedHooks
    {}

    function initializePostLockerSetup(
        PoolKey calldata poolKey,
        address lpLocker,
        bool clankerIsToken0
    ) external onlyApprovedHooks {
        // grab the deployed clanker and paired token
        address clanker = clankerIsToken0
            ? Currency.unwrap(poolKey.currency0)
            : Currency.unwrap(poolKey.currency1);
        address pairedToken = clankerIsToken0
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);

        // check that the token's paired token is the input token
        if (pairedToken != inputToken) {
            revert ClankerNotPairedWithTargetInputToken();
        }

        // get reward info from the locker
        IClankerLpLocker.TokenRewardInfo memory tokenRewardInfo =
            IClankerLpLocker(lpLocker).tokenRewards(clanker);

        // check that the token reward recipient is this address
        if (tokenRewardInfo.rewardRecipients[0] != address(this)) {
            revert InvalidFirstFeeRecipient();
        }

        // check that the token reward admin is the dead address to prevent the
        // reward recipient from being updated
        if (tokenRewardInfo.rewardAdmins[0] != address(0x000000000000000000000000000000000000dEaD))
        {
            revert InvalidFirstFeeAdmin();
        }

        // check that this fee recipient is only getting the fees in paired token
        if (
            IClankerLpLockerFeeConversion(lpLocker).feePreferences(clanker, 0)
                != IClankerLpLockerFeeConversion.FeeIn.Paired
        ) {
            revert InvalidFirstFeePreference();
        }

        // log fee BPS for observability
        uint16 feeBps = tokenRewardInfo.rewardBps[0];

        emit PoolInitialized(poolKey.toId(), clanker, feeBps);
    }

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bool,
        bytes calldata
    ) external onlyApprovedHooks {
        // claim rewards from the locker
        if (feeLocker.availableFees(address(this), inputToken) > 0) {
            feeLocker.claim(address(this), inputToken);
        }

        // if we have no fees to swap, return
        if (IERC20(inputToken).balanceOf(address(this)) == 0) {
            return;
        }

        // grab amount of token to use for the swap
        uint256 amountIn = IERC20(inputToken).balanceOf(address(this));

        // approve the swap router for the amount to spend
        SafeERC20.forceApprove(IERC20(inputToken), address(uniV3Router), amountIn);

        // build the swap params
        ISwapRouterV3.ExactInputSingleParams memory swapBackParams = ISwapRouterV3
            .ExactInputSingleParams({
            tokenIn: inputToken,
            tokenOut: outputToken,
            fee: uniV3Fee,
            recipient: buyBackRecipient,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // swap the fees for the output token
        uint256 amountOut = uniV3Router.exactInputSingle(swapBackParams);

        // record the amount swapped
        emit SwappedBack(inputToken, outputToken, amountIn, amountOut);
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner {
        (bool success,) = payable(recipient).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address token, address recipient) public onlyOwner {
        IERC20 token_ = IERC20(token);
        SafeERC20.safeTransfer(token_, recipient, token_.balanceOf(address(this)));
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
