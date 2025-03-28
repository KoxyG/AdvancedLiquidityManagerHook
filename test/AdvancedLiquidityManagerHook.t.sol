// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import {Test} from "forge-std/Test.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {Currency} from "v4-core/src/types/Currency.sol";
// import {AdvancedLiquidityManagerHook} from "../src/AdvancedLiquidityManagerHook.sol";
// // import {HookTest} from "./utils/HookTest.sol";
// import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
// import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";


// contract AdvancedLiquidityManagerHookTest is Test {
//     using PoolIdLibrary for PoolKey;

//     AdvancedLiquidityManagerHook hook;
//     PoolKey poolKey;
//     address manager;
    
//     function setUp() public {
//         // Create a mock manager address
//         manager = address(0x123);
        
//         // Deploy the hook
//         hook = new AdvancedLiquidityManagerHook(IPoolManager(manager));
        
//         // Create a test pool key
//         poolKey = PoolKey({
//             currency0: Currency.wrap(address(0x1)),
//             currency1: Currency.wrap(address(0x2)),
//             fee: 3000,
//             tickSpacing: 60,
//             hooks: hook
//         });
//     }

//     // function test_FeeAdjustmentOnVolatility() public {
//     //     // Simulate some swaps to build up volatility
//     //     for(uint i = 0; i < 5; i++) {
//     //         // Create swap params
//     //         IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
//     //             zeroForOne: true,
//     //             amountSpecified: 1000e18,
//     //             sqrtPriceLimitX96: 0
//     //         });

//     //         // Simulate price changes
//     //         BalanceDelta delta = BalanceDelta.wrap(int256((1000e18 << 128) | 900e18));
            
//     //         // Call afterSwap
//     //         hook.afterSwap(address(this), poolKey, params, delta, "");
            
//     //         // Move time forward
//     //         vm.warp(block.timestamp + 1 hours);
//     //     }

//     //     // Check if volatility triggered higher fees
//     //     uint24 fee = hook.getFee(poolKey);
//     //     assertEq(fee, hook.BASE_FEE() * 2, "Fee should be doubled due to high volatility");
//     // }

//     // function test_StablecoinPoolFees() public {
//     //     // Mark as stablecoin pool
//     //     hook.setStablecoinPool(poolKey.toId(), true);

//     //     // Check fee
//     //     uint24 fee = hook.getFee(poolKey);
//     //     assertEq(fee, hook.STABLECOIN_BASE_FEE(), "Should use lower fee for stablecoin pool");
//     // }

//     // function test_GasPriceAdjustment() public {
//     //     // Set high gas price
//     //     vm.setGasPrice(1000 gwei);
        
//     //     // Update moving average
//     //     hook.updateMovingAverage();
        
//     //     // Check if fee is halved
//     //     uint24 fee = hook.getFee(poolKey);
//     //     assertEq(fee, hook.BASE_FEE() / 2, "Fee should be halved due to high gas price");
//     // }

//     function test_VolumeTracking() public {
//         // Simulate a swap
//         IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
//             zeroForOne: true,
//             amountSpecified: 1000e18,
//             sqrtPriceLimitX96: 0
//         });

//         BalanceDelta delta = BalanceDelta.wrap(int256((1000e18 << 128) | 900e18));
        
//         // Execute swap
//         hook.afterSwap(address(this), poolKey, params, delta, "");
        
//         // Check volume tracking
//         (uint256 volume,,,) = hook.poolAnalytics(poolKey.toId());
//         assertGt(volume, 0, "Volume should be tracked");
//     }
// } 