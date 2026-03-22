import { WAD } from '../config/contracts';

/**
 * Calculate PnL for a position with proper BigInt handling
 */
export function calculatePositionPnL(
  isLong: boolean,
  entryPI: bigint,
  currentPI: bigint,
  positionSize: bigint
): bigint {
  console.log('[calculatePositionPnL] Input values:', {
    isLong,
    entryPI: entryPI.toString(),
    currentPI: currentPI.toString(),
    positionSize: positionSize.toString(),
    WAD: WAD.toString()
  });

  try {
    // Prevent division by zero and handle edge cases
    if (positionSize === BigInt(0) || entryPI === currentPI) {
      console.log('[calculatePositionPnL] Zero position size or no price change, returning 0');
      return BigInt(0);
    }

    // Calculate price difference in WAD units
    const priceDiff = currentPI - entryPI;
    const direction = isLong ? 1 : -1;

    console.log('[calculatePositionPnL] Calculation steps:', {
      priceDiff: priceDiff.toString(),
      direction,
      priceDiffNumber: Number(priceDiff),
      positionSizeNumber: Number(positionSize),
      WADNumber: Number(WAD)
    });

    // Calculate PnL: (currentPI - entryPI) * positionSize * direction
    // We need to be careful with BigInt arithmetic
    const priceDiffBig = priceDiff * BigInt(direction);
    const pnlBig = (priceDiffBig * positionSize) / WAD;

    console.log('[calculatePositionPnL] BigInt calculation:', {
      priceDiffBig: priceDiffBig.toString(),
      pnlBig: pnlBig.toString()
    });

    // Double-check with floating point calculation for comparison
    const pnlFloat = (direction * Number(priceDiff) * Number(positionSize)) / Number(WAD);
    const pnlFloatBigInt = BigInt(Math.round(pnlFloat));

    console.log('[calculatePositionPnL] Comparison with float calculation:', {
      pnlFloat,
      pnlFloatBigInt: pnlFloatBigInt.toString(),
      difference: (pnlBig - pnlFloatBigInt).toString()
    });

    return pnlBig;
  } catch (error) {
    console.error('[calculatePositionPnL] Error calculating PnL:', error);
    return BigInt(0);
  }
}

/**
 * Calculate net PnL after fees and funding
 */
export function calculateNetPnL(
  grossPnL: bigint,
  borrowFees: bigint,
  fundingAccrued: bigint
): bigint {
  console.log('[calculateNetPnL] Input values:', {
    grossPnL: grossPnL.toString(),
    borrowFees: borrowFees.toString(),
    fundingAccrued: fundingAccrued.toString()
  });

  try {
    const netPnL = grossPnL - borrowFees + fundingAccrued;

    console.log('[calculateNetPnL] Result:', {
      netPnL: netPnL.toString()
    });

    return netPnL;
  } catch (error) {
    console.error('[calculateNetPnL] Error calculating net PnL:', error);
    return grossPnL; // Fallback to gross PnL
  }
}

/**
 * Calculate position equity: collateral + PnL - fees + funding
 */
export function calculateEquity(
  collateral: bigint,
  grossPnL: bigint,
  borrowFees: bigint,
  fundingAccrued: bigint
): bigint {
  console.log('[calculateEquity] Input values:', {
    collateral: collateral.toString(),
    grossPnL: grossPnL.toString(),
    borrowFees: borrowFees.toString(),
    fundingAccrued: fundingAccrued.toString()
  });

  try {
    const equity = collateral + grossPnL - borrowFees + fundingAccrued;

    console.log('[calculateEquity] Result:', {
      equity: equity.toString()
    });

    return equity;
  } catch (error) {
    console.error('[calculateEquity] Error calculating equity:', error);
    return collateral; // Fallback to collateral only
  }
}

/**
 * Format PnL value for display with proper sign
 */
export function formatPnL(value: bigint): string {
  console.log('[formatPnL] Formatting value:', value.toString());

  try {
    const num = Number(value) / Number(WAD);
    console.log('[formatPnL] Converted to number:', num);

    if (!isFinite(num) || isNaN(num)) {
      console.warn('[formatPnL] Non-finite number, returning $0.00');
      return '$0.00';
    }

    const prefix = num >= 0 ? '+' : '';
    const formatted = `${prefix}$${Math.abs(num).toFixed(2)}`;

    console.log('[formatPnL] Final formatted value:', formatted);
    return formatted;
  } catch (error) {
    console.error('[formatPnL] Error formatting PnL:', error);
    return '$0.00';
  }
}

/**
 * Format price value for display as percentage
 */
export function formatPrice(price: bigint): string {
  console.log('[formatPrice] Formatting price:', price.toString());

  try {
    const num = Number(price) / Number(WAD) * 100;
    console.log('[formatPrice] Converted to percentage:', num);

    if (!isFinite(num) || isNaN(num)) {
      console.warn('[formatPrice] Non-finite number, returning 0.0c');
      return '0.0c';
    }

    const formatted = `${Math.max(0, num).toFixed(1)}c`;
    console.log('[formatPrice] Final formatted price:', formatted);
    return formatted;
  } catch (error) {
    console.error('[formatPrice] Error formatting price:', error);
    return '0.0c';
  }
}

/**
 * Get color class for PnL display
 */
export function getPnLColor(value: bigint): string {
  if (value > BigInt(0)) return 'text-accent';
  if (value < BigInt(0)) return 'text-danger';
  return 'text-gray-500';
}