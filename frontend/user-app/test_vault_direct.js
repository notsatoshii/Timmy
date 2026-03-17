const { createPublicClient, http } = require('viem');
const { baseSepolia } = require('viem/chains');

// Contract addresses from fallback in frontend
const CONTRACT_ADDRESSES = {
  leverVault: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921",
  usdt: "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E",
  oiLimits: "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd",
};

// Simple ABI for the functions we need
const LEVER_VAULT_ABI = [
  {
    "type": "function",
    "name": "totalAssets",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalSupply",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "convertToAssets",
    "inputs": [{ "name": "shares", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  }
];

const OI_LIMITS_ABI = [
  {
    "type": "function",
    "name": "getGlobalOI",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  }
];

async function testVaultData() {
  console.log('=== DIRECT VAULT DATA TEST ===');

  // Create client
  const client = createPublicClient({
    chain: baseSepolia,
    transport: http('https://sepolia.base.org')
  });

  try {
    console.log('Testing contract addresses:', CONTRACT_ADDRESSES);

    // Test individual calls
    console.log('\n=== INDIVIDUAL CALLS ===');

    const totalAssets = await client.readContract({
      address: CONTRACT_ADDRESSES.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalAssets',
    });
    console.log('totalAssets:', totalAssets.toString());

    const totalSupply = await client.readContract({
      address: CONTRACT_ADDRESSES.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalSupply',
    });
    console.log('totalSupply:', totalSupply.toString());

    const WAD = BigInt('1000000000000000000'); // 1e18
    const sharePrice = await client.readContract({
      address: CONTRACT_ADDRESSES.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'convertToAssets',
      args: [WAD],
    });
    console.log('sharePrice (convertToAssets 1 WAD):', sharePrice.toString());

    const globalOI = await client.readContract({
      address: CONTRACT_ADDRESSES.oiLimits,
      abi: OI_LIMITS_ABI,
      functionName: 'getGlobalOI',
    });
    console.log('globalOI:', globalOI.toString());

    // Calculate derived values
    console.log('\n=== CALCULATED VALUES ===');

    // TVL (totalAssets is in USDT format, 6 decimals)
    const tvl = Number(totalAssets) / 1e6;
    console.log('TVL (USD):', tvl.toLocaleString());

    // Share price (sharePrice is in WAD format from convertToAssets)
    const sharePriceFloat = Number(sharePrice) / 1e18;
    console.log('Share Price (USD):', sharePriceFloat);

    // Utilization (globalOI is in USDT format, 6 decimals)
    const globalOIFloat = Number(globalOI) / 1e6;
    const utilization = tvl > 0 ? (globalOIFloat / tvl) * 100 : 0;
    console.log('Utilization (%):', utilization.toFixed(2));

    console.log('\n=== MULTICALL TEST ===');

    // Test multicall (this is what wagmi uses internally)
    const multicallResult = await client.multicall({
      contracts: [
        {
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalAssets',
        },
        {
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalSupply',
        },
        {
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'convertToAssets',
          args: [WAD],
        },
        {
          address: CONTRACT_ADDRESSES.oiLimits,
          abi: OI_LIMITS_ABI,
          functionName: 'getGlobalOI',
        }
      ]
    });

    console.log('Multicall results:');
    multicallResult.forEach((result, index) => {
      const names = ['totalAssets', 'totalSupply', 'sharePrice', 'globalOI'];
      if (result.status === 'success') {
        console.log(`  ${names[index]}: ${result.result.toString()}`);
      } else {
        console.error(`  ${names[index]}: ERROR -`, result.error);
      }
    });

  } catch (error) {
    console.error('Error testing vault data:', error.message);
    console.error('Stack:', error.stack);
  }
}

testVaultData().catch(console.error);