import { useMemo } from 'react';
import { formatWad, WAD } from '../config/contracts';

interface VaultData {
  totalAssets?: bigint;
  totalSupply?: bigint;
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
    const {
      totalAssets = BigInt(0),
      totalSupply = BigInt(0),
      borrowFees = BigInt(0),
      transactionFees = BigInt(0),
      liquidationFees = BigInt(0),
      settlementFees = BigInt(0),
      globalOI = BigInt(0),
      userShares = BigInt(0),
      usdtBalance = BigInt(0),
    } = data;

    // TVL calculation
    const tvl = totalAssets ? parseFloat(formatWad(totalAssets)) : 0;

    // Share price calculation (assets per share)
    const sharePrice = totalSupply > BigInt(0) && totalAssets > BigInt(0)
      ? parseFloat(formatWad(totalAssets)) / parseFloat(formatWad(totalSupply))
      : 1.0;

    // Utilization calculation (OI / TVL)
    const utilization = tvl > 0 && globalOI > BigInt(0)
      ? (parseFloat(formatWad(globalOI)) / tvl) * 100
      : 0;

    // APY calculation from total fees (LP gets 50%)
    const totalFees = borrowFees + transactionFees + liquidationFees + settlementFees;
    const lpFeeShare = totalFees * BigInt(50) / BigInt(100); // LP gets 50% of all fees
    const annualizedAPY = tvl > 0 && totalFees > BigInt(0)
      ? (parseFloat(formatWad(lpFeeShare)) * 365 / tvl) * 100
      : 0;

    // Daily yield from APY
    const dailyYield = annualizedAPY / 365;

    // User position calculations
    const userSharesFloat = userShares ? parseFloat(formatWad(userShares)) : 0;
    const userPosition = {
      shares: userSharesFloat,
      value: userSharesFloat * sharePrice,
      percentage: totalSupply > BigInt(0) ? (userSharesFloat / parseFloat(formatWad(totalSupply))) * 100 : 0,
    };

    // User balance calculations
    const usdtFloat = usdtBalance ? parseFloat(formatWad(usdtBalance)) : 0;
    const userBalance = {
      usdt: usdtFloat,
      formatted: usdtFloat.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }),
    };

    return {
      tvl,
      sharePrice,
      utilization,
      annualizedAPY,
      dailyYield,
      userPosition,
      userBalance,
    };
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