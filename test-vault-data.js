const { createPublicClient, http, parseUnits } = require('viem');
const { baseSepolia } = require('viem/chains');

// Contract addresses from deployment
const LEVER_VAULT_ADDRESS = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';
const OI_LIMITS_ADDRESS = '0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd';

// Simple ABI for the functions we need to test
const VAULT_ABI = [
  {
    name: 'totalAssets',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalSupply',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'convertToAssets',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'shares', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
];

const OI_LIMITS_ABI = [
  {
    name: 'getGlobalOI',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
];

async function testVaultData() {
  console.log('=== TESTING VAULT DATA FETCHING ===');

  const client = createPublicClient({
    chain: baseSepolia,
    transport: http(),
  });

  try {
    // Test individual calls to ensure contracts are working
    console.log('\n--- Testing individual contract calls ---');

    const totalAssets = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'totalAssets',
    });
    console.log('totalAssets:', totalAssets.toString(), `($${Number(totalAssets) / 1e6})`);

    const totalSupply = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'totalSupply',
    });
    console.log('totalSupply:', totalSupply.toString(), `(${Number(totalSupply) / 1e18} shares)`);

    // Test convertToAssets(1 WAD) - this is what the frontend uses for share price
    const WAD = parseUnits('1', 18);
    const sharePrice = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'convertToAssets',
      args: [WAD],
    });
    console.log('sharePrice (convertToAssets):', sharePrice.toString(), `($${Number(sharePrice) / 1e6})`);

    const globalOI = await client.readContract({
      address: OI_LIMITS_ADDRESS,
      abi: OI_LIMITS_ABI,
      functionName: 'getGlobalOI',
    });
    console.log('globalOI:', globalOI.toString(), `($${Number(globalOI) / 1e6})`);

    // Calculate metrics like the frontend would
    console.log('\n--- Calculated metrics ---');
    const tvl = Number(totalAssets) / 1e6;
    const sharePriceFloat = Number(sharePrice) / 1e6; // sharePrice is in USDT format
    const supplyFloat = Number(totalSupply) / 1e18;
    const oiFloat = Number(globalOI) / 1e6;
    const utilization = (oiFloat / tvl) * 100;

    console.log('TVL:', `$${tvl.toLocaleString()}`);
    console.log('Share Price:', `$${sharePriceFloat.toFixed(4)}`);
    console.log('Total Shares:', supplyFloat.toLocaleString());
    console.log('Global OI:', `$${oiFloat.toLocaleString()}`);
    console.log('Utilization:', `${utilization.toFixed(2)}%`);

    // Check for NaN values
    const hasNaN = [tvl, sharePriceFloat, supplyFloat, oiFloat, utilization].some(val =>
      !isFinite(val) || isNaN(val)
    );

    if (hasNaN) {
      console.log('\n❌ FOUND NaN OR INFINITE VALUES - ISSUE NOT FIXED');
    } else {
      console.log('\n✅ ALL VALUES ARE FINITE AND VALID - ISSUE APPEARS FIXED');
    }

    // Test multicall (simulating what the frontend does)
    console.log('\n--- Testing multicall like frontend ---');
    const multicallResults = await client.multicall({
      contracts: [
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'totalAssets',
        },
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'totalSupply',
        },
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'convertToAssets',
          args: [WAD],
        },
        {
          address: OI_LIMITS_ADDRESS,
          abi: OI_LIMITS_ABI,
          functionName: 'getGlobalOI',
        },
      ],
    });

    console.log('Multicall results:');
    multicallResults.forEach((result, index) => {
      const names = ['totalAssets', 'totalSupply', 'sharePrice', 'globalOI'];
      console.log(`  ${names[index]}:`, result.status === 'success' ? result.result.toString() : `ERROR: ${result.error?.message}`);
    });

  } catch (error) {
    console.error('Error testing vault data:', error);
  }
}

testVaultData();