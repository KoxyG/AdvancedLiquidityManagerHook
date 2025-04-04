// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

abstract contract MockPoolManager is IPoolManager {
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24 tick) {
        return 0;
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        return "";
    }

    function donate(PoolKey calldata key, uint256 amount0, uint256 amount1) external payable {}

    function take(PoolKey calldata key, int256 delta0, int256 delta1) external returns (BalanceDelta) {
        return toBalanceDelta(int128(delta0), int128(delta1));
    }

    function swap(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData) external returns (BalanceDelta) {
        return toBalanceDelta(0, 0);
    }

    function setProtocolFeeController(address protocolFeeController) external {}

    function setProtocolFee(PoolKey calldata key, uint24 fee) external {}

    function collectProtocolFees(Currency currency) external returns (uint256) {
        return 0;
    }

    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return 0;
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) external view returns (uint256[] memory) {
        return new uint256[](owners.length);
    }

    function isOperator(address owner, address spender) external view returns (bool) {
        return false;
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        return true;
    }

    function approve(address spender, uint256 id, uint256 amount) external returns (bool) {
        return true;
    }

    function allowance(address owner, address spender, uint256 id) external view returns (uint256) {
        return 0;
    }

    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool) {
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool) {
        return true;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return bytes32(0);
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory) {
        return new bytes32[](nSlots);
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        return new bytes32[](slots.length);
    }

    function exttload(bytes32 slot) external view returns (bytes32) {
        return bytes32(0);
    }

    function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        return new bytes32[](slots.length);
    }
} 