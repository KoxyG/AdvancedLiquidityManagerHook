// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

contract AdvancedLiquidityManagerHook is BaseHook {
    using LPFeeLibrary for uint24;

    // Keeping track of the moving average gas price
    uint128 public movingAverageGasPrice;
    // How many times has the moving average been updated?
    // Needed as the denominator to update it the next time based on the moving average formula
    uint104 public movingAverageGasPriceCount;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // denominated in pips (one-hundredth bps) 0.5%
    uint256 public constant HIGH_VOLATILITY_THRESHOLD = 1000; // 10% price change threshold

    error MustUseDynamicFee();

    // Add new state variables for analytics and cross-chain data
    struct PoolAnalytics {
        uint256 totalVolume;
        uint256 totalSwaps;
        uint256 lastPrice;
        uint256 volatility;
        uint256 lastUpdateTimestamp;
    }
    
    mapping(PoolId => PoolAnalytics) public poolAnalytics;
    
    // Track stablecoin pools separately
    mapping(PoolId => bool) public isStablecoinPool;
    uint24 public constant STABLECOIN_BASE_FEE = 100; // 0.01% for stables
    
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        updateMovingAverage();
    }

    function setStablecoinPool(PoolId poolId, bool isStable) public {
        isStablecoinPool[poolId] = isStable;
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `LPFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

   

    function getFee(PoolKey calldata key) public view returns (uint24) {
        PoolId poolId = PoolIdLibrary.toId(key);
        
        // Use lower fees for stablecoin pools
        if (isStablecoinPool[poolId]) {
            return STABLECOIN_BASE_FEE;
        }
        
        uint128 gasPrice = uint128(tx.gasprice);
        PoolAnalytics storage analytics = poolAnalytics[poolId];

        // Adjust fees based on volatility
        if (analytics.volatility > HIGH_VOLATILITY_THRESHOLD) {
            return BASE_FEE * 2;
        }

        // if gasPrice > movingAverageGasPrice * 1.1, then half the fees
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        // if gasPrice < movingAverageGasPrice * 0.9, then double the fees
        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }

        return BASE_FEE;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // afterSwap
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = PoolIdLibrary.toId(key);
        
        // Update analytics
        PoolAnalytics storage analytics = poolAnalytics[poolId];
        analytics.totalSwaps++;
        analytics.totalVolume += uint256(abs(delta.amount0()));
        
        // Calculate and update price volatility
        uint256 currentPrice = calculatePrice(delta);
        if (analytics.lastPrice > 0) {
            analytics.volatility = calculateVolatility(
                currentPrice,
                analytics.lastPrice,
                analytics.lastUpdateTimestamp
            );
        }
        analytics.lastPrice = currentPrice;
        analytics.lastUpdateTimestamp = block.timestamp;
        
        // Update moving average gas price
        updateMovingAverage();
        
        return (BaseHook.afterSwap.selector, 0);
    }


     function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = getFee(key);
        // poolManager.updateDynamicLPFee(key, fee);
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }

    // getHookData
    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }

    function parseHookData(bytes calldata data) public pure returns (address user) {
        return abi.decode(data, (address));
    }

    // Update our moving average gas price
    function updateMovingAverage() public {
        uint128 gasPrice = uint128(tx.gasprice);

        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    // Helper functions
    function calculatePrice(BalanceDelta delta) 
        public pure returns (uint256) {
        // Get absolute values of the swap amounts
        uint256 amount0 = uint256(abs(delta.amount0()));
        uint256 amount1 = uint256(abs(delta.amount1()));
        
        // Avoid division by zero
        if (amount0 == 0) return 0;
        
        // Calculate price as amount1/amount0
        // Multiply by 1e18 for fixed-point precision
        return (amount1 * 1e18) / amount0;
    }

    function calculateVolatility(
        uint256 currentPrice,
        uint256 lastPrice,
        uint256 lastUpdateTime
    ) public view returns (uint256) {
        // Calculate time elapsed since last update (in seconds)
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0) return 0;

        // Calculate absolute price change percentage
        // If currentPrice > lastPrice: (currentPrice - lastPrice) * 100 / lastPrice
        // If currentPrice < lastPrice: (lastPrice - currentPrice) * 100 / lastPrice
        uint256 priceChange;
        if (currentPrice > lastPrice) {
            priceChange = ((currentPrice - lastPrice) * 10000) / lastPrice;
        } else {
            priceChange = ((lastPrice - currentPrice) * 10000) / lastPrice;
        }

        // Normalize volatility to a per-hour basis
        // 3600 = seconds in an hour
        return (priceChange * 3600) / timeElapsed;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
