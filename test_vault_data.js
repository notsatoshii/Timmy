// Test script to check vault data directly
import { createPublicClient, http } from 'viem';
import { baseSepolia } from 'viem/chains';

const client = createPublicClient({
  chain: baseSepolia,
  transport: http('https://sepolia.base.org')
});

const LEVER_VAULT_ADDRESS = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';
const OI_LIMITS_ADDRESS = '0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd';
const USDT_ADDRESS = '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E';

// Basic ERC4626 ABI for vault functions we need
const VAULT_ABI = [
  {
    "inputs": [],
    "name": "totalAssets",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "uint256", "name": "shares", "type": "uint256" }],
    "name": "convertToAssets",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }
];

const OI_LIMITS_ABI = [
  {
    "inputs": [],
    "name": "getGlobalOI",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  }
];

async function testVaultData() {
  try {
    console.log('🔍 Testing vault data...');

    // Test individual calls
    console.log('\n--- Individual Contract Calls ---');

    const totalAssets = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'totalAssets'
    });
    console.log('Total Assets:', totalAssets.toString());

    const totalSupply = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'totalSupply'
    });
    console.log('Total Supply:', totalSupply.toString());

    const WAD = BigInt('1000000000000000000'); // 1e18
    const sharePrice = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'convertToAssets',
      args: [WAD]
    });
    console.log('Share Price (WAD):', sharePrice.toString());

    const globalOI = await client.readContract({
      address: OI_LIMITS_ADDRESS,
      abi: OI_LIMITS_ABI,
      functionName: 'getGlobalOI'
    });
    console.log('Global OI:', globalOI.toString());

    // Test multicall
    console.log('\n--- Multicall Test ---');

    const multicallResults = await client.multicall({
      contracts: [
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'totalAssets'
        },
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'totalSupply'
        },
        {
          address: LEVER_VAULT_ADDRESS,
          abi: VAULT_ABI,
          functionName: 'convertToAssets',
          args: [WAD]
        },
        {
          address: OI_LIMITS_ADDRESS,
          abi: OI_LIMITS_ABI,
          functionName: 'getGlobalOI'
        }
      ]
    });

    console.log('Multicall Results:', multicallResults.map((result, i) => ({
      index: i,
      status: result.status,
      result: result.status === 'success' ? result.result?.toString() : result.error?.message
    })));

    // Calculate metrics
    if (totalAssets && totalSupply && sharePrice) {
      console.log('\n--- Calculated Metrics ---');

      // TVL (totalAssets is in USDT format - 6 decimals)
      const tvl = Number(totalAssets) / 1e6;
      console.log('TVL: $' + tvl.toLocaleString());

      // Share price (sharePrice is already per-share in USDT format)
      const sharePriceFormatted = Number(sharePrice) / 1e6;
      console.log('Share Price: $' + sharePriceFormatted.toFixed(4));

      // Utilization
      const utilization = totalAssets > 0 ? (Number(globalOI) / Number(totalAssets)) * 100 : 0;
      console.log('Utilization: ' + utilization.toFixed(2) + '%');

      // Check for NaN
      if (isNaN(tvl) || isNaN(sharePriceFormatted) || isNaN(utilization)) {
        console.error('❌ Found NaN values!', { tvl, sharePriceFormatted, utilization });
      } else {
        console.log('✅ All values are valid numbers');
      }
    }

  } catch (error) {
    console.error('❌ Error testing vault data:', error);
  }
}

testVaultData();