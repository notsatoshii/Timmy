// Test the insurance fund formatting fix
const { formatUsdt } = require('./src/config/contracts');

// The problematic value from health check: 5011000000005000000000000 [5.011e24]
const rawValue = BigInt('5011000000005000000000000');
console.log('Raw insurance fund value (WAD format):', rawValue.toString());

// Convert from WAD to USDT format (divide by 1e12)
const wadToUsdtDivisor = BigInt('1000000000000'); // 1e12
const usdtValue = rawValue / wadToUsdtDivisor;
console.log('After WAD→USDT conversion:', usdtValue.toString());

// Format for display
const formatted = formatUsdt(usdtValue);
console.log('Final formatted value:', formatted);

// Expected bootstrap value for comparison
const expectedBootstrap = BigInt('10000') * BigInt('1000000'); // $10K in USDT format
const expectedFormatted = formatUsdt(expectedBootstrap);
console.log('Expected $10K bootstrap formatted:', expectedFormatted);

// Test with the original bootstrap value in WAD format
const bootstrapWad = BigInt('10000') * BigInt('1000000000000000000'); // 10,000e18
console.log('Bootstrap in WAD format:', bootstrapWad.toString());
const bootstrapConverted = bootstrapWad / wadToUsdtDivisor;
console.log('Bootstrap converted to USDT:', bootstrapConverted.toString());
const bootstrapFormatted = formatUsdt(bootstrapConverted);
console.log('Bootstrap formatted:', bootstrapFormatted);