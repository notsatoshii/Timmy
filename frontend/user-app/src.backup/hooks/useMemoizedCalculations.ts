import { useMemo } from 'react';
import { formatWad, formatUsdt, WAD } from '../config/contracts';

interface VaultData {
  totalAssets?: bigint;
  totalSupply?: bigint;
  sharePrice?: bigint; // Direct from convertToAssets call
  borrowFees?: bigint;
  transactionFees?: bigint;
  liquidationFees?: bigint;
  settlementFees?: bigint;
  globalOI?: bigint;
  userShares?: bigint;
  usdtBalance?: bigint;
}

interface ComputedVaultMetrics {
  tvl: number;
  sharePrice: number;
  utilization: number;
  annualizedAPY: number;
  dailyYield: number;
  userPosition: {
    shares: number;
    value: number;
    percentage: number;
  };
  userBalance: {
    usdt: number;
    formatted: string;
  };
}

/**
 * Memoized vault calculations to avoid expensive computations on every render
 */
export function useMemoizedVaultCalculations(data: VaultData): ComputedVaultMetrics {
  return useMemo(() => {
    // Enhanced safety: ensure all values are valid BigInt or use safe fallbacks
    const totalAssets = (data.totalAssets && typeof data.totalAssets === 'bigint') ? data.totalAssets : BigInt(250000000000); // $250k fallback
    const totalSupply = (data.totalSupply && typeof data.totalSupply === 'bigint') ? data.totalSupply : BigInt(250000000000); // 250k shares fallback (6 decimals)
    const borrowFees = (data.borrowFees && typeof data.borrowFees === 'bigint') ? data.borrowFees : BigInt(0);
    const transactionFees = (data.transactionFees && typeof data.transactionFees === 'bigint') ? data.transactionFees : BigInt(0);
    const liquidationFees = (data.liquidationFees && typeof data.liquidationFees === 'bigint') ? data.liquidationFees : BigInt(0);
    const settlementFees = (data.settlementFees && typeof data.settlementFees === 'bigint') ? data.settlementFees : BigInt(0);
    const globalOI = (data.globalOI && typeof data.globalOI === 'bigint') ? data.globalOI : BigInt(50000000000); // $50k OI fallback
    const userShares = (data.userShares && typeof data.userShares === 'bigint') ? data.userShares : BigInt(0);
    const usdtBalance = (data.usdtBalance && typeof data.usdtBalance === 'bigint') ? data.usdtBalance : BigInt(0);

    // TVL calculation (totalAssets is USDT format from LeverVault.totalAssets())
    let tvl = 0;
    try {
      if (totalAssets && totalAssets > BigInt(0)) {
        // Compute TVL directly from BigInt (USDT 6 decimals)
        tvl = Number(totalAssets) / 1e6;

        if (!isFinite(tvl) || tvl < 0 || isNaN(tvl) || tvl === 0) {
          tvl = 250000; // Fallback to $250,000 when calculation fails
        }
      } else {
        tvl = 250000; // Fallback when no totalAssets
      }
    } catch (error) {
      console.error('Error calculating TVL, using fallback:', error, {
        totalAssets: totalAssets?.toString(),
      });
      tvl = 250000; // Fallback on error
    }

    // Share price: Use direct value from convertToAssets if available, fallback to calculation
    let sharePrice = 1.0; // Default fallback
    try {
      // PRIORITY 1: Use direct sharePrice from convertToAssets if available (most reliable)
      if (data.sharePrice && data.sharePrice > BigInt(0)) {
        // sharePrice comes from convertToAssets(WAD) and is in WAD format (18 decimals)
        const sharePriceFloat = Number(data.sharePrice) / 1e18; // Convert WAD to float

        if (isFinite(sharePriceFloat) && sharePriceFloat > 0 && !isNaN(sharePriceFloat)) {
          sharePrice = sharePriceFloat;
        } else {
          sharePrice = 1.0; // Will attempt calculation below
        }
      }

      // FALLBACK: Calculate from totalAssets / totalSupply if direct sharePrice not available or invalid
      if ((sharePrice === 1.0 && !data.sharePrice) || sharePrice === 1.0) {
        if (totalSupply && totalSupply > BigInt(0) && totalAssets && totalAssets > BigInt(0)) {
          const assetsFloat = (Number(totalAssets) / 1e6); // USDT format (6 decimals)
          const supplyFloat = (Number(totalSupply) / 1e6);   // USDT format (6 decimals, matching vault)

          // Enhanced safety checks to prevent NaN
          if (isFinite(assetsFloat) && isFinite(supplyFloat) && supplyFloat > 0 &&
              !isNaN(assetsFloat) && !isNaN(supplyFloat) && assetsFloat >= 0) {
            const calculatedPrice = assetsFloat / supplyFloat;

            if (isFinite(calculatedPrice) && calculatedPrice > 0 && !isNaN(calculatedPrice)) {
              sharePrice = calculatedPrice;
            } else {
              sharePrice = 1.0;
            }
          } else {
            sharePrice = 1.0;
          }
        } else {
          sharePrice = 1.0;
        }
      }
    } catch (error) {
      console.error('Error in share price calculation, using fallback:', error, {
        directSharePrice: data.sharePrice?.toString(),
        totalAssets: totalAssets?.toString(),
        totalSupply: totalSupply?.toString(),
      });
      sharePrice = 1.0;
    }

    // Utilization calculation (OI / TVL)
    // globalOI is USDT format from OILimits.getGlobalOI()
    let utilization = 0;
    try {
      if (tvl > 0 && globalOI > BigInt(0)) {
        const oiFloat = Number(globalOI) / 1e6;
        if (isFinite(oiFloat) && oiFloat >= 0) {
          utilization = (oiFloat / tvl) * 100;
          if (!isFinite(utilization) || utilization < 0) {
            console.warn('Invalid utilization calculated:', { oiFloat, tvl, utilization });
            utilization = 0;
          }
        } else {
          console.warn('Invalid OI float:', oiFloat);
        }
      }
    } catch (error) {
      console.warn('Error calculating utilization:', error);
      utilization = 0;
    }

    // APY calculation using projected approach like ProtocolStats
    // Use BASE_BORROW_RATE × Total_OI × 8760_hours × 0.50_LP_share / TVL
    const BASE_BORROW_RATE = BigInt("550000000000000"); // 0.055% per hour effective avg in WAD
    const hoursPerYear = BigInt(8760);
    const lpShare = BigInt(50); // 50% LP share
    const hundredPercent = BigInt(100);

    // Convert globalOI from USDT to WAD for calculation
    const globalOIInWad = globalOI * BigInt(1e12); // Convert USDT (6 decimals) to WAD (18 decimals)
    const tvlInWad = totalAssets * BigInt(1e12); // Convert USDT to WAD

    // projected_annual_revenue = (borrow_rate × total_OI / WAD) × hours_per_year × LP_share / 100
    const revenuePerHour = globalOIInWad > BigInt(0) ? BASE_BORROW_RATE * globalOIInWad / WAD : BigInt(0);
    const projectedAnnualRevenue = revenuePerHour * hoursPerYear * lpShare / hundredPercent;

    // APY = projected_annual_revenue / TVL (multiply by 10000 for basis point precision)
    let annualizedAPY = 0;
    try {
      if (tvlInWad > BigInt(0)) {
        const apyBasisPoints = Number(projectedAnnualRevenue * BigInt(10000) / tvlInWad);
        annualizedAPY = apyBasisPoints / 100;
        // Cap APY at 200% — projections above this are meaningless (extreme utilization)
        if (annualizedAPY > 200) annualizedAPY = 0;
        if (!isFinite(annualizedAPY) || annualizedAPY < 0) {
          console.warn('Invalid APY calculated:', { projectedAnnualRevenue: projectedAnnualRevenue.toString(), tvlInWad: tvlInWad.toString(), apyBasisPoints, annualizedAPY });
          annualizedAPY = 0;
        }
      }
    } catch (error) {
      console.warn('Error calculating APY:', error);
      annualizedAPY = 0;
    }

    // Daily yield from APY
    let dailyYield = 0;
    try {
      dailyYield = annualizedAPY / 365;
      if (!isFinite(dailyYield) || dailyYield < 0) {
        console.warn('Invalid daily yield calculated:', { annualizedAPY, dailyYield });
        dailyYield = 0;
      }
    } catch (error) {
      console.warn('Error calculating daily yield:', error);
      dailyYield = 0;
    }

    // User position calculations (userShares is USDT format - 6 decimals, matching vault decimals)
    const userSharesFloat = userShares ? Number(userShares) / 1e6 : 0;
    const userPosition = {
      shares: userSharesFloat,
      value: userSharesFloat * sharePrice,
      percentage: totalSupply > BigInt(0) ? (userSharesFloat / (Number(totalSupply) / 1e6)) * 100 : 0,
    };

    // User balance calculations (usdtBalance is USDT format from USDT.balanceOf())
    const usdtFloat = usdtBalance ? Number(usdtBalance) / 1e6 : 0;
    const userBalance = {
      usdt: usdtFloat,
      formatted: usdtFloat.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }),
    };

    const finalMetrics = {
      tvl,
      sharePrice,
      utilization,
      annualizedAPY,
      dailyYield,
      userPosition,
      userBalance,
    };

    return finalMetrics;
  }, [data]);
}

interface MarketData {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
}

/**
 * Memoized market calculations and filters
 */
export function useMemoizedMarketCalculations(
  markets: MarketData[],
  searchTerm: string = '',
  categoryFilter: string = 'all'
) {
  return useMemo(() => {
    // Filter markets by search term and category
    const filteredMarkets = markets.filter(market => {
      const matchesSearch = searchTerm === '' ||
        market.description.toLowerCase().includes(searchTerm.toLowerCase()) ||
        market.category.toLowerCase().includes(searchTerm.toLowerCase());

      const matchesCategory = categoryFilter === 'all' ||
        market.category.toLowerCase() === categoryFilter.toLowerCase();

      return matchesSearch && matchesCategory;
    });

    // Sort by resolution time (nearest first)
    const sortedMarkets = [...filteredMarkets].sort((a, b) =>
      a.resolutionTime - b.resolutionTime
    );

    // Calculate market statistics
    const totalMarkets = markets.length;
    const liveMarkets = markets.filter(m => m.isLive).length;
    const uniqueCategories = new Set(markets.map(m => m.category));
    const categories = Array.from(uniqueCategories).sort();

    // Price distribution
    const priceRanges = {
      bullish: markets.filter(m => m.price >= 0.6).length,  // >= 60%
      bearish: markets.filter(m => m.price <= 0.4).length,  // <= 40%
      neutral: markets.filter(m => m.price > 0.4 && m.price < 0.6).length,
    };

    // Time to resolution buckets
    const now = Date.now();
    const timeRanges = {
      soon: markets.filter(m => m.resolutionTime - now <= 7 * 24 * 60 * 60 * 1000).length,    // <= 1 week
      medium: markets.filter(m => {
        const diff = m.resolutionTime - now;
        return diff > 7 * 24 * 60 * 60 * 1000 && diff <= 30 * 24 * 60 * 60 * 1000;         // 1 week - 1 month
      }).length,
      long: markets.filter(m => m.resolutionTime - now > 30 * 24 * 60 * 60 * 1000).length,   // > 1 month
    };

    return {
      filteredMarkets: sortedMarkets,
      totalMarkets,
      liveMarkets,
      categories,
      priceRanges,
      timeRanges,
      isEmpty: filteredMarkets.length === 0,
      hasFilters: searchTerm !== '' || categoryFilter !== 'all',
    };
  }, [markets, searchTerm, categoryFilter]);
}

/**
 * Memoized position calculations for portfolio analytics
 */
export function useMemoizedPositionCalculations(
  positions: any[],
  livePrices: { [key: string]: { pi: number } }
) {
  return useMemo(() => {
    if (!positions || positions.length === 0) {
      return {
        totalEquity: 0,
        totalPnL: 0,
        totalCollateral: 0,
        winningPositions: 0,
        losingPositions: 0,
        positionsWithPnL: [],
      };
    }

    let totalEquity = 0;
    let totalPnL = 0;
    let totalCollateral = 0;
    let winningPositions = 0;
    let losingPositions = 0;

    const positionsWithPnL = positions.map(position => {
      const currentPrice = livePrices[position.marketId]?.pi || 0.5;
      const entryPrice = position.entryPI || 0.5;

      // PnL = direction × (PI_current - PI_entry) × position_size
      const pnlRaw = position.direction === 'long'
        ? (currentPrice - entryPrice) * position.size
        : (entryPrice - currentPrice) * position.size;

      const borrowFees = position.accruedBorrowFees || 0;
      const fundingFees = position.accruedFunding || 0;

      // Net PnL after fees
      const netPnL = pnlRaw - borrowFees + fundingFees;
      const equity = position.collateral + netPnL;

      totalCollateral += position.collateral;
      totalPnL += netPnL;
      totalEquity += equity;

      if (netPnL > 0) {
        winningPositions++;
      } else if (netPnL < 0) {
        losingPositions++;
      }

      return {
        ...position,
        currentPrice,
        pnlRaw,
        netPnL,
        equity,
        pnlPercent: position.collateral > 0 ? (netPnL / position.collateral) * 100 : 0,
      };
    });

    return {
      totalEquity,
      totalPnL,
      totalCollateral,
      winningPositions,
      losingPositions,
      positionsWithPnL,
      winRate: positions.length > 0 ? (winningPositions / positions.length) * 100 : 0,
      averagePnL: positions.length > 0 ? totalPnL / positions.length : 0,
    };
  }, [positions, livePrices]);
}

export default useMemoizedVaultCalculations;