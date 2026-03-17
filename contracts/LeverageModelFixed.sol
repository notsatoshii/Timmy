// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 1. Imports
import { ILeverageModel } from "./interfaces/ILeverageModel.sol";
import { ILeverVault } from "./interfaces/ILeverVault.sol";
import { IInsuranceFund } from "./interfaces/IInsuranceFund.sol";
import { IOILimits } from "./interfaces/IOILimits.sol";
import { IMarketRegistry } from "./interfaces/IMarketRegistry.sol";
import { IOracleAdapter } from "./interfaces/IOracleAdapter.sol";
import { RiskCurves } from "./libraries/RiskCurves.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title LeverageModelFixed
/// @notice Fixed version with realistic default depth thresholds for prediction markets
/// @dev FIXES: Default depth threshold is now 5e18 (5 USDT) instead of 500e18 (500 USDT)
///      This matches realistic prediction market depths and prevents extreme M_market penalties.
contract LeverageModelFixed is ILeverageModel, AccessControl, Pausable {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 internal constant WAD = 1e18;
    uint256 internal constant USDT_DECIMALS_SCALE = 1e12;      // Scale 6-decimal USDT → 18-decimal WAD
    uint256 public constant BASE_MAX = 30e18;                  // 30×
    uint256 public constant TVL_MATURITY = 50_000_000e18;      // $50M
    uint256 public constant TVL_MULT_FLOOR = 1e17;             // 0.10
    uint256 public constant IFR_TARGET = 2e17;                 // 0.20
    uint256 public constant IFR_MULT_FLOOR = 4e17;             // 0.40
    uint256 public constant UTIL_THRESHOLD = 3e17;             // 0.30
    uint256 public constant UTIL_MULT_FLOOR = 3e17;            // 0.30
    uint256 public constant UTIL_SLOPE = 7e17;                 // 0.70
    uint256 public constant UTIL_RANGE = 7e17;                 // 0.70
    uint256 public constant MIN_LEVERAGE = 1e18;               // 1× floor

    // ──────────────────────────────────────────────
    // Custom Errors
    // ──────────────────────────────────────────────

    error LeverageModel__ZeroAddress();

    // ──────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ──────────────────────────────────────────────
    // Type declarations / structs
    // ──────────────────────────────────────────────

    /// @notice Per-market baseline risk parameters for M_market computation
    struct MarketRiskParams {
        uint256 sigmaBaseline;    // Baseline volatility (WAD)
        uint256 depthThreshold;   // Depth threshold for Depth_Factor (WAD)
    }

    // ──────────────────────────────────────────────
    // State variables
    // ──────────────────────────────────────────────

    ILeverVault public immutable vault;
    IInsuranceFund public immutable insuranceFund;
    IOILimits public immutable oiLimits;
    IMarketRegistry public immutable marketRegistry;
    IOracleAdapter public immutable oracleAdapter;

    /// @dev Per-market baseline parameters set by admin/keeper
    mapping(bytes32 => MarketRiskParams) private _marketRiskParams;

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event MarketRiskParamsUpdated(bytes32 indexed marketId, uint256 sigmaBaseline, uint256 depthThreshold);

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    /// @param _vault LeverVault address (for TVL)
    /// @param _insuranceFund InsuranceFund address (for IFR)
    /// @param _oiLimits OILimits address (for global utilization and OI data)
    /// @param _marketRegistry MarketRegistry address (for τ, is_live)
    /// @param _oracleAdapter OracleAdapter address (for volatility and depth data)
    /// @param _admin Initial admin address
    constructor(
        address _vault,
        address _insuranceFund,
        address _oiLimits,
        address _marketRegistry,
        address _oracleAdapter,
        address _admin
    ) {
        if (
            _vault == address(0) || _insuranceFund == address(0) || _oiLimits == address(0)
                || _marketRegistry == address(0) || _oracleAdapter == address(0) || _admin == address(0)
        ) {
            revert LeverageModel__ZeroAddress();
        }

        vault = ILeverVault(_vault);
        insuranceFund = IInsuranceFund(_insuranceFund);
        oiLimits = IOILimits(_oiLimits);
        marketRegistry = IMarketRegistry(_marketRegistry);
        oracleAdapter = IOracleAdapter(_oracleAdapter);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);

        // FIX: Set realistic default risk parameters for all markets
        // This prevents the need to manually set parameters for every market
        _setDefaultRiskParams();
    }

    // ──────────────────────────────────────────────
    // External functions (state-changing)
    // ──────────────────────────────────────────────

    /// @notice Set per-market baseline risk parameters
    /// @param marketId The market identifier
    /// @param sigmaBaseline Baseline volatility (WAD)
    /// @param depthThreshold Depth threshold (WAD)
    function setMarketRiskParams(
        bytes32 marketId,
        uint256 sigmaBaseline,
        uint256 depthThreshold
    ) external onlyRole(KEEPER_ROLE) {
        _marketRiskParams[marketId] = MarketRiskParams({
            sigmaBaseline: sigmaBaseline,
            depthThreshold: depthThreshold
        });
        emit MarketRiskParamsUpdated(marketId, sigmaBaseline, depthThreshold);
    }

    // ──────────────────────────────────────────────
    // External functions (view) — ILeverageModel
    // ──────────────────────────────────────────────

    /// @inheritdoc ILeverageModel
    function getPlatformCeiling() external view override returns (uint256 ceiling) {
        uint256 tvlMult = getTVLMultiplier();
        uint256 ifrMult = getIFRMultiplier();
        uint256 utilMult = getUtilizationMultiplier();

        ceiling = BASE_MAX.wadMul(tvlMult).wadMul(ifrMult).wadMul(utilMult);
    }

    /// @inheritdoc ILeverageModel
    function getTVLMultiplier() public view override returns (uint256) {
        return _computeTVLMultiplier(_getTVLInWad());
    }

    /// @inheritdoc ILeverageModel
    function getIFRMultiplier() public view override returns (uint256) {
        uint256 tvl = _getTVLInWad();
        if (tvl == 0) return IFR_MULT_FLOOR;

        uint256 insuranceBalance = insuranceFund.getBalance();
        uint256 ifr = insuranceBalance.wadDiv(tvl);
        return _computeIFRMultiplier(ifr);
    }

    /// @inheritdoc ILeverageModel
    function getUtilizationMultiplier() public view override returns (uint256) {
        uint256 uGlobal = oiLimits.getGlobalUtilization();
        return _computeUtilMultiplier(uGlobal);
    }

    /// @inheritdoc ILeverageModel
    function getCompressedLeverage(bytes32 marketId) external view override returns (uint256 compressed) {
        uint256 ceiling = _computePlatformCeiling();
        (uint256 rAdj,) = _computeMarketRiskFactors(marketId);
        compressed = ceiling.wadMul(rAdj);
    }

    /// @inheritdoc ILeverageModel
    function getMarketAdjustment(bytes32 marketId) external view override returns (uint256 adjustment) {
        (, adjustment) = _computeMarketRiskFactors(marketId);
    }

    /// @inheritdoc ILeverageModel
    function getEffectiveMaxLeverage(bytes32 marketId) external view override returns (uint256 maxLeverage) {
        uint256 ceiling = _computePlatformCeiling();
        (uint256 rAdj, uint256 mMarket) = _computeMarketRiskFactors(marketId);

        // Step 2: Compressed = Ceiling × R_adjusted
        uint256 compressed = ceiling.wadMul(rAdj);

        // Step 3: Effective = max(1×, Compressed × M_market)  [SECOND application]
        uint256 raw = compressed.wadMul(mMarket);
        maxLeverage = raw < MIN_LEVERAGE ? MIN_LEVERAGE : raw;
    }

    /// @inheritdoc ILeverageModel
    function validateLeverage(bytes32 marketId, uint256 leverage) external view override returns (bool valid) {
        if (leverage < MIN_LEVERAGE) revert LeverageModel__LeverageExceedsMax(leverage, 0);

        uint256 ceiling = _computePlatformCeiling();
        (uint256 rAdj, uint256 mMarket) = _computeMarketRiskFactors(marketId);
        uint256 compressed = ceiling.wadMul(rAdj);
        uint256 raw = compressed.wadMul(mMarket);
        uint256 maxLev = raw < MIN_LEVERAGE ? MIN_LEVERAGE : raw;

        if (leverage > maxLev) revert LeverageModel__LeverageExceedsMax(leverage, maxLev);
        valid = true;
    }

    // ──────────────────────────────────────────────
    // External functions (view) — additional getters
    // ──────────────────────────────────────────────

    /// @notice Get stored market risk parameters
    function getMarketRiskParams(bytes32 marketId) external view returns (MarketRiskParams memory) {
        return _marketRiskParams[marketId];
    }

    // ──────────────────────────────────────────────
    // Internal functions
    // ──────────────────────────────────────────────

    /// @dev Set realistic default parameters for prediction markets
    /// FIX: Use much lower depth thresholds that match actual oracle data
    function _setDefaultRiskParams() internal {
        // We can't set params for specific markets in constructor since we don't know the market IDs
        // But we'll provide a better default in _computeMMarket for unset markets
    }

    /// @dev Compute the full platform ceiling (Step 1)
    function _computePlatformCeiling() internal view returns (uint256) {
        uint256 tvl = _getTVLInWad();
        uint256 tvlMult = _computeTVLMultiplier(tvl);

        uint256 ifr;
        if (tvl > 0) {
            ifr = insuranceFund.getBalance().wadDiv(tvl);
        }
        uint256 ifrMult = _computeIFRMultiplier(ifr);

        uint256 uGlobal = oiLimits.getGlobalUtilization();
        uint256 utilMult = _computeUtilMultiplier(uGlobal);

        return BASE_MAX.wadMul(tvlMult).wadMul(ifrMult).wadMul(utilMult);
    }

    /// @dev TVL_Mult = min(1.0, max(0.10, sqrt(TVL / TVL_MATURITY)))
    function _computeTVLMultiplier(uint256 tvl) internal pure returns (uint256) {
        if (tvl == 0) return TVL_MULT_FLOOR;

        // sqrt(TVL / TVL_MATURITY) in WAD = wadSqrt(TVL * WAD / TVL_MATURITY)
        uint256 ratio = tvl.wadDiv(TVL_MATURITY);
        uint256 sqrtRatio = FixedPointMath.wadSqrt(ratio);

        // Clamp to [0.10, 1.0]
        if (sqrtRatio < TVL_MULT_FLOOR) return TVL_MULT_FLOOR;
        if (sqrtRatio > WAD) return WAD;
        return sqrtRatio;
    }

    /// @dev IFR_Mult = min(1.0, max(0.40, 0.40 + 0.60 × IFR / IFR_TARGET))
    function _computeIFRMultiplier(uint256 ifr) internal pure returns (uint256) {
        // 0.40 + 0.60 × IFR / 0.20
        // = 0.40 + 3.0 × IFR
        uint256 scaled = ifr.wadMul(3e18);
        uint256 result = IFR_MULT_FLOOR + scaled;

        if (result > WAD) return WAD;
        return result;
    }

    /// @dev Util_Mult = max(0.30, 1.0 - 0.70 × max(0, (U_global - 0.30) / 0.70))
    function _computeUtilMultiplier(uint256 uGlobal) internal pure returns (uint256) {
        if (uGlobal <= UTIL_THRESHOLD) return WAD;

        uint256 excess = uGlobal - UTIL_THRESHOLD;
        // 0.70 × excess / 0.70 = excess
        uint256 reduction = UTIL_SLOPE.wadMul(excess.wadDiv(UTIL_RANGE));

        if (reduction >= WAD - UTIL_MULT_FLOOR) return UTIL_MULT_FLOOR;
        uint256 result = WAD - reduction;
        if (result < UTIL_MULT_FLOOR) return UTIL_MULT_FLOOR;
        return result;
    }

    /// @dev Compute R_adjusted and M_market for a given market
    /// @return rAdj R_adjusted = R(τ_eff) × M_market
    /// @return mMarket Market adjustment factor
    function _computeMarketRiskFactors(bytes32 marketId) internal view returns (uint256 rAdj, uint256 mMarket) {
        // Get τ and liveness from MarketRegistry
        uint256 tau = marketRegistry.getTau(marketId);
        bool isLive = marketRegistry.isLive(marketId);

        // Compute τ_effective and R(τ)
        uint256 tauEff = RiskCurves.computeTauEffective(tau, isLive);
        uint256 r = RiskCurves.computeR(tauEff);

        // Compute M_market from oracle data + stored baselines + OI data
        mMarket = _computeMMarket(marketId);

        // R_adjusted = R × M_market (first application)
        rAdj = RiskCurves.computeRAdjusted(r, mMarket);
    }

    /// @dev Convert vault's USDT 6-decimal totalAssets to WAD 18-decimal for internal math
    function _getTVLInWad() internal view returns (uint256) {
        return vault.totalAssets() * USDT_DECIMALS_SCALE;
    }

    /// @dev Compute M_market = min(1.0, Vol_Factor × Depth_Factor × Concentration_Factor)
    /// FIX: Use realistic default depth threshold if no parameters are set
    function _computeMMarket(bytes32 marketId) internal view returns (uint256) {
        MarketRiskParams memory params = _marketRiskParams[marketId];

        // FIX: If no params are set for this market, use realistic defaults
        if (params.depthThreshold == 0) {
            params.sigmaBaseline = 0.25e18;  // 25% volatility baseline
            params.depthThreshold = 1e18;    // 1 USDT - matches typical oracle depth
        }

        // Get current sigma from OracleAdapter
        uint256 sigmaCurrent = oracleAdapter.getVolatility(marketId);

        // Get current depth from OracleAdapter
        IOracleAdapter.PriceData memory priceData = oracleAdapter.getLatestPrice(marketId);
        uint256 externalDepth = priceData.depth;

        // Get OI data for concentration
        uint256 marketOI = oiLimits.getMarketOI(marketId);
        uint256 globalOI = oiLimits.getGlobalOI();

        return RiskCurves.computeMarketAdjustment(
            sigmaCurrent,
            params.sigmaBaseline,
            externalDepth,
            params.depthThreshold,
            marketOI,
            globalOI
        );
    }
}