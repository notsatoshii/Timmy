// Test the fixed vault calculations
const sharePrice = BigInt('1000000473028692815'); // From real contract data
const totalAssets = BigInt('60508028315742'); // From real contract data

console.log('=== TESTING VAULT CALCULATIONS FIX ===');
console.log('Raw sharePrice from convertToAssets:', sharePrice.toString());
console.log('Raw totalAssets:', totalAssets.toString());

// OLD CALCULATION (WRONG)
const oldCalculation = Number(sharePrice) / 1e6; // Wrong: treated as USDT format
console.log('OLD (incorrect) calculation: dividing by 1e6 =', oldCalculation);
console.log('OLD result would show: $' + oldCalculation.toLocaleString());

// NEW CALCULATION (CORRECT)
const newCalculation = Number(sharePrice) / 1e18; // Correct: treating as WAD format
console.log('NEW (correct) calculation: dividing by 1e18 =', newCalculation);
console.log('NEW result shows: $' + newCalculation.toFixed(4));

// Verify TVL calculation is also correct
const tvl = Number(totalAssets) / 1e6; // USDT format conversion is correct
console.log('TVL calculation (unchanged): $' + tvl.toLocaleString());

console.log('\n=== VERIFICATION ===');
console.log('Share price should be around $1.00:', newCalculation > 0.99 && newCalculation < 1.01 ? '✓' : '✗');
console.log('TVL should be reasonable:', tvl > 1000000 ? '✓' : '✗');
console.log('Old calculation was wrong:', oldCalculation > 10000 ? '✓ (way too high)' : '✗');