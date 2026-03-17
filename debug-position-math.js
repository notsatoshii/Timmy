// Simple debugging script to test position value calculations

// Constants from the frontend code
const WAD = BigInt('1000000000000000000'); // 1e18
console.log('WAD:', WAD.toString());

// Helper function from frontend
const formatWad = (value) => {
  const num = Number(value) / Number(WAD);
  console.log(`formatWad: ${value.toString()} -> ${num} -> ${num.toFixed(2)}`);
  return num.toFixed(2);
};

// Test demo position data (from baseDemoPositions[0])
const testPosition = {
  id: BigInt(1),
  marketName: 'SpaceX IPO by Dec 2026',
  isLong: true,
  collateral: BigInt(1000) * WAD, // 1000 USDT
  positionSize: BigInt(5000) * WAD, // 5000 notional
  entryPI: BigInt(350) * WAD / BigInt(1000), // 0.35 PI
  entryPrice: BigInt(355) * WAD / BigInt(1000), // 0.355 entry price
  currentPI: BigInt(380) * WAD / BigInt(1000), // 0.38 PI
  borrowFees: BigInt(12) * WAD, // 12 USDT borrow fees
  fundingAccrued: BigInt(-3) * WAD, // -3 USDT funding
};

console.log('\n=== TEST POSITION VALUES ===');
console.log('Raw BigInt values:');
console.log('  collateral:', testPosition.collateral.toString());
console.log('  positionSize:', testPosition.positionSize.toString());
console.log('  entryPI:', testPosition.entryPI.toString());
console.log('  currentPI:', testPosition.currentPI.toString());
console.log('  borrowFees:', testPosition.borrowFees.toString());
console.log('  fundingAccrued:', testPosition.fundingAccrued.toString());

console.log('\nFormatted values:');
console.log('  collateral: $' + formatWad(testPosition.collateral));
console.log('  positionSize: $' + formatWad(testPosition.positionSize));
console.log('  borrowFees: $' + formatWad(testPosition.borrowFees));
console.log('  fundingAccrued: $' + formatWad(testPosition.fundingAccrued));

// Test PnL calculation (from the frontend code)
console.log('\n=== PnL CALCULATION ===');
const priceDiff = Number(testPosition.currentPI - testPosition.entryPI);
const direction = testPosition.isLong ? 1 : -1;
const pnlValue = direction * priceDiff * Number(testPosition.positionSize) / Number(WAD);
const pnlBigInt = BigInt(Math.round(pnlValue));

console.log('PnL calculation steps:');
console.log('  entryPI (number):', Number(testPosition.entryPI) / Number(WAD));
console.log('  currentPI (number):', Number(testPosition.currentPI) / Number(WAD));
console.log('  priceDiff:', priceDiff);
console.log('  priceDiff (as WAD units):', priceDiff / Number(WAD));
console.log('  direction:', direction);
console.log('  positionSize (number):', Number(testPosition.positionSize));
console.log('  WAD (number):', Number(WAD));
console.log('  pnlValue (raw):', pnlValue);
console.log('  pnlBigInt:', pnlBigInt.toString());
console.log('  pnlFormatted: $' + formatWad(pnlBigInt));

// Test equity calculation
const equity = testPosition.collateral + pnlBigInt - testPosition.borrowFees + testPosition.fundingAccrued;
console.log('\n=== EQUITY CALCULATION ===');
console.log('  collateral:', testPosition.collateral.toString());
console.log('  + pnl:', pnlBigInt.toString());
console.log('  - borrowFees:', testPosition.borrowFees.toString());
console.log('  + fundingAccrued:', testPosition.fundingAccrued.toString());
console.log('  = equity:', equity.toString());
console.log('  equityFormatted: $' + formatWad(equity));

// Test formatPnl function
const formatPnl = (value) => {
  try {
    const num = Number(value) / Number(WAD);
    if (!isFinite(num) || isNaN(num)) {
      return '$0.00';
    }
    const prefix = num >= 0 ? '+' : '';
    return `${prefix}$${Math.abs(num).toFixed(2)}`;
  } catch (error) {
    console.warn('Error formatting PnL:', error);
    return '$0.00';
  }
};

console.log('\n=== FORMAT PnL TEST ===');
console.log('  pnl BigInt:', pnlBigInt.toString());
console.log('  formatPnl result:', formatPnl(pnlBigInt));

console.log('\n=== SUMMARY ===');
console.log('All values should be non-zero for a profitable position:');
console.log('  Collateral: $' + formatWad(testPosition.collateral));
console.log('  PnL: ' + formatPnl(pnlBigInt));
console.log('  Equity: $' + formatWad(equity));
console.log('\nIf any show $0.00, there\'s a calculation or formatting issue.');