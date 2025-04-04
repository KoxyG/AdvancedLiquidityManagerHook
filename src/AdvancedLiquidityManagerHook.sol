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
import {Currency} from "v4-core/src/types/Currency.sol";

import {IPositionManager} from './interface/IPositionManager.sol';
import {IRevenueManager} from './interface/IRevenueManager.sol';
import {ITreasuryManagerFactory} from './interface/ITreasuryManagerFactory.sol';


contract AdvancedLiquidityManagerHook is BaseHook {
    using LPFeeLibrary for uint24;

    // Gas price tracking for dynamic fee adjustments
    uint128 public movingAverageGasPrice;    // Current moving average of gas prices
    uint104 public movingAverageGasPriceCount; // Number of updates for moving average

    // Fee configuration constants
    uint24 public constant BASE_FEE = 5000; // 0.5% base fee
    uint256 public constant HIGH_VOLATILITY_THRESHOLD = 1000; // 10% price change threshold
    uint24 public constant STABLECOIN_BASE_FEE = 100; // 0.01% for stablecoin pairs

    error MustUseDynamicFee();

    // Analytics tracking for each pool
    struct PoolAnalytics {
        uint256 totalVolume;      // Total trading volume
        uint256 totalSwaps;       // Number of swaps executed
        uint256 lastPrice;        // Last recorded price
        uint256 volatility;       // Current volatility metric
        uint256 lastUpdateTimestamp; // Last update time
    }

    // Flaunch token information for ETH pairs
    struct FlaunchToken {
        address memecoin;         // Token address
        uint tokenId;            // Unique token identifier
        address payable manager;  // Treasury manager address
    }
    
    // Immutable contract references
    address public immutable managerImplementation;
    IPositionManager public immutable positionManager;
    ITreasuryManagerFactory public immutable treasuryManagerFactory;

    // Pool state mappings
    mapping(PoolId => FlaunchToken) public flaunchTokens;     // Tracks flaunch tokens for ETH pairs
    mapping(PoolId => bool) public isNativePool;              // Identifies pools containing ETH
    mapping(PoolId => bool) public isStablecoinPool;          // Identifies stablecoin pairs
    mapping(PoolId => PoolAnalytics) public poolAnalytics;    // Stores pool analytics data

    constructor(
        IPoolManager _poolManager,
        address _positionManager,
        address _treasuryManagerFactory,
        address _managerImplementation
    ) BaseHook(_poolManager) {
        positionManager = IPositionManager(_positionManager);
        treasuryManagerFactory = ITreasuryManagerFactory(_treasuryManagerFactory);
        managerImplementation = _managerImplementation;
        updateMovingAverage();
    }

    /// @notice Initializes a new pool and creates flaunch token for ETH pairs
    /// @param key The pool key containing pool parameters
    function _afterInitialize(address, PoolKey calldata key, uint160) internal returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        
        // Check if this is a native ETH pool
        if (Currency.unwrap(key.currency0) == address(0)) {
            PoolId poolId = PoolIdLibrary.toId(key);
            isNativePool[poolId] = true;
            
            // Create flaunch token with custom parameters
            address memecoin = positionManager.flaunch(
                IPositionManager.FlaunchParams({
                    name: 'Advanced Liquidity Manager',
                    symbol: 'ALM',
                    tokenUri: 'https://lavender-electric-gerbil-466.mypinata.cloud/ipfs/bafybeichocyvocmrrixgunzlrcnj4u7sbg3cst54mp3e3begu4qiphe3jq',
                    initialTokenFairLaunch: 50e27,
                    premineAmount: 0,
                    creator: address(this),
                    creatorFeeAllocation: 10_00, // 10% fees
                    flaunchAt: 0,
                    initialPriceParams: abi.encode(''),
                    feeCalculatorParams: abi.encode(1_000)
                })
            );

            // Get the token ID for the flaunch token
            uint tokenId = positionManager.flaunchContract().tokenId(memecoin);
            address payable manager = treasuryManagerFactory.deployManager(managerImplementation);

            // Initialize manager with revenue sharing parameters
            positionManager.flaunchContract().approve(manager, tokenId);
            IRevenueManager(manager).initialize(
                IRevenueManager.FlaunchToken(positionManager.flaunchContract(), tokenId),
                address(this),
                abi.encode(
                    IRevenueManager.InitializeParams(
                        payable(address(this)),
                        payable(address(this)),
                        100_00
                    )
                )
            );

            // Store flaunch token information
            flaunchTokens[poolId] = FlaunchToken({
                memecoin: memecoin,
                tokenId: tokenId,
                manager: manager
            });
        }
        
        return this.beforeInitialize.selector;
    }

    /// @notice Sets whether a pool is a stablecoin pair
    /// @param poolId The ID of the pool to configure
    /// @param isStable Whether the pool contains stablecoins
    function setStablecoinPool(PoolId poolId, bool isStable) external {
        isStablecoinPool[poolId] = isStable;
    }

    /// @notice Calculates the appropriate fee based on pool type and market conditions
    /// @param key The pool key containing pool parameters
    /// @return The calculated fee in basis points
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

        // Adjust fees based on gas price
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }

        return BASE_FEE;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
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
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _claimAndDonateFees(key);
        uint24 fee = getFee(key);
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

    /// @notice Updates the moving average gas price for fee adjustments
    function updateMovingAverage() public {
        uint128 gasPrice = uint128(tx.gasprice);

        // Calculate new moving average
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    /// @notice Calculates the current price from swap amounts
    /// @param delta The balance delta from the swap
    /// @return The calculated price in fixed-point format
    function calculatePrice(BalanceDelta delta) public pure returns (uint256) {
        uint256 amount0 = uint256(abs(delta.amount0()));
        uint256 amount1 = uint256(abs(delta.amount1()));
        
        if (amount0 == 0) return 0;
        
        return (amount1 * 1e18) / amount0;
    }

    /// @notice Calculates price volatility over time
    /// @param currentPrice The current price
    /// @param lastPrice The previous price
    /// @param lastUpdateTime The timestamp of the last update
    /// @return The calculated volatility metric
    function calculateVolatility(
        uint256 currentPrice,
        uint256 lastPrice,
        uint256 lastUpdateTime
    ) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0) return 0;

        uint256 priceChange;
        if (currentPrice > lastPrice) {
            priceChange = ((currentPrice - lastPrice) * 10000) / lastPrice;
        } else {
            priceChange = ((lastPrice - currentPrice) * 10000) / lastPrice;
        }

        return (priceChange * 3600) / timeElapsed;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    /// @notice Claims and donates collected fees back to the pool
    /// @param key The pool key containing pool parameters
    function _claimAndDonateFees(PoolKey calldata key) internal {
        PoolId poolId = key.toId();

        // Check if this is a native pool with a flaunch token
        FlaunchToken memory flaunchToken = flaunchTokens[poolId];
        if (flaunchToken.tokenId == 0) {
            return;
        }

        // Withdraw fees from revenue manager
        (, uint ethReceived) = IRevenueManager(flaunchToken.manager).claim();

        // Donate fees back to the pool if any were received
        if (ethReceived > 0) {
            poolManager.donate({
                key: key,
                amount0: ethReceived,
                amount1: 0,
                hookData: ''
            });
        }
    }

    receive() external payable {}
}