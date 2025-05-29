// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ClankerHook} from "./ClankerHook.sol";
import {IClankerHookStaticFee} from "./interfaces/IClankerHookStaticFee.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {console} from "forge-std/console.sol";

contract ClankerHookStaticFee is ClankerHook, IClankerHookStaticFee {
    mapping(PoolId => uint24) public clankerFee;
    mapping(PoolId => uint24) public pairedFee;

    constructor(address _poolManager, address _factory, address _locker, address _weth)
        ClankerHook(_poolManager, _factory, _locker, _weth)
    {}

    function _initializePoolData(PoolKey memory poolKey, bytes memory poolData) internal override {
        PoolStaticConfigVars memory _poolConfigVars = abi.decode(poolData, (PoolStaticConfigVars));

        if (_poolConfigVars.clankerFee > MAX_LP_FEE) {
            revert ClankerFeeTooHigh();
        }

        if (_poolConfigVars.pairedFee > MAX_LP_FEE) {
            revert PairedFeeTooHigh();
        }

        clankerFee[poolKey.toId()] = _poolConfigVars.clankerFee;
        pairedFee[poolKey.toId()] = _poolConfigVars.pairedFee;

        emit PoolInitialized(poolKey.toId(), _poolConfigVars.clankerFee, _poolConfigVars.pairedFee);
    }

    // set the LP fee according to the clanker/paired fee configuration
    function _setFee(PoolKey calldata poolKey, IPoolManager.SwapParams calldata swapParams)
        internal
        override
    {
        uint24 fee = swapParams.zeroForOne != clankerIsToken0[poolKey.toId()]
            ? pairedFee[poolKey.toId()]
            : clankerFee[poolKey.toId()];

        _setProtocolFee(fee);
        IPoolManager(poolManager).updateDynamicLPFee(poolKey, fee);
    }
}
