// Simple test to see what's happening with vault data
console.log('=== VAULT ISSUE INVESTIGATION ===');

// Simulate the calculations that happen in the frontend
function testVaultCalculations() {
  // These are the problematic values that might be causing NaN
  const scenarios = [
    {
      name: 'undefined sharePrice',
      totalAssets: BigInt('250000000000'),
      totalSupply: BigInt('250000000000000000000000'),
      sharePrice: undefined,
      globalOI: BigInt('50000000000')
    },
    {
      name: 'null sharePrice',
      totalAssets: BigInt('250000000000'),
      totalSupply: BigInt('250000000000000000000000'),
      sharePrice: null,
      globalOI: BigInt('50000000000')
    },
    {
      name: 'zero sharePrice',
      totalAssets: BigInt('250000000000'),
      totalSupply: BigInt('250000000000000000000000'),
      sharePrice: BigInt('0'),
      globalOI: BigInt('50000000000')
    },
    {
      name: 'valid sharePrice',
      totalAssets: BigInt('250000000000'),
      totalSupply: BigInt('250000000000000000000000'),
      sharePrice: BigInt('1000000473028692815'),
      globalOI: BigInt('50000000000')
    }
  ];

  scenarios.forEach(scenario => {
    console.log(`\n--- Testing: ${scenario.name} ---`);
    
    let sharePrice = 1.0; // Default fallback
    
    try {
      if (scenario.sharePrice && scenario.sharePrice > BigInt(0)) {
        const sharePriceFloat = Number(scenario.sharePrice) / 1e18;
        if (isFinite(sharePriceFloat) && sharePriceFloat > 0 && !isNaN(sharePriceFloat)) {
          sharePrice = sharePriceFloat;
          console.log('Using direct share price:', sharePrice);
        } else {
          console.log('Invalid direct share price, using fallback');
        }
      } else {
        console.log('No valid sharePrice, calculating from totalAssets/totalSupply');
        
        if (scenario.totalSupply && scenario.totalSupply > BigInt(0) && scenario.totalAssets && scenario.totalAssets > BigInt(0)) {
          const assetsFloat = Number(scenario.totalAssets) / 1e6; // USDT format
          const supplyFloat = Number(scenario.totalSupply) / 1e18; // WAD format
          
          if (isFinite(assetsFloat) && isFinite(supplyFloat) && supplyFloat > 0) {
            const calculatedPrice = assetsFloat / supplyFloat;
            if (isFinite(calculatedPrice) && calculatedPrice > 0 && !isNaN(calculatedPrice)) {
              sharePrice = calculatedPrice;
              console.log('Using calculated share price:', sharePrice);
            }
          }
        }
      }
      
      // Test TVL calculation
      const tvl = Number(scenario.totalAssets) / 1e6;
      console.log(`TVL: $${tvl.toLocaleString()}`);
      console.log(`Share Price: $${sharePrice.toFixed(4)}`);
      console.log(`Is NaN: ${isNaN(sharePrice) ? 'YES ❌' : 'NO ✓'}`);
      console.log(`Is Finite: ${isFinite(sharePrice) ? 'YES ✓' : 'NO ❌'}`);
      
    } catch (error) {
      console.error('Error in calculations:', error.message);
      console.log(`Would show NaN: YES ❌`);
    }
  });
}

testVaultCalculations();
