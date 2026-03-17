const { createPublicClient, http } = require('viem');
const { baseSepolia } = require('viem/chains');

// Contract addresses from deployment
const contracts = {
  leverVault: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921",
  oiLimits: "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd",
  usdt: "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E"
};

// Minimal ABI for testing
const LEVER_VAULT_ABI = [
  {
    "inputs": [],
    "name": "totalAssets",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "shares", "type": "uint256"}],
    "name": "convertToAssets",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

const OI_LIMITS_ABI = [
  {
    "inputs": [],
    "name": "getGlobalOI",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

const USDT_ABI = [
  {
    "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

async function testVaultRPC() {
  console.log('=== VAULT RPC DEBUG ===');

  const client = createPublicClient({
    chain: baseSepolia,
    transport: http()
  });

  const WAD = BigInt('1000000000000000000'); // 1e18

  try {
    console.log('Testing individual contract calls...');

    // Test totalAssets
    console.log('\n1. Testing totalAssets...');
    const totalAssets = await client.readContract({
      address: contracts.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalAssets',
    });
    console.log(`✓ totalAssets: ${totalAssets.toString()} (${Number(totalAssets) / 1e6} USDT)`);

    // Test totalSupply
    console.log('\n2. Testing totalSupply...');
    const totalSupply = await client.readContract({
      address: contracts.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalSupply',
    });
    console.log(`✓ totalSupply: ${totalSupply.toString()} (${Number(totalSupply) / 1e18} shares)`);

    // Test sharePrice
    console.log('\n3. Testing sharePrice (convertToAssets)...');
    const sharePrice = await client.readContract({
      address: contracts.leverVault,
      abi: LEVER_VAULT_ABI,
      functionName: 'convertToAssets',
      args: [WAD],
    });
    console.log(`✓ sharePrice: ${sharePrice.toString()} (${Number(sharePrice) / 1e12} USDT per share)`);

    // Test globalOI
    console.log('\n4. Testing globalOI...');
    const globalOI = await client.readContract({
      address: contracts.oiLimits,
      abi: OI_LIMITS_ABI,
      functionName: 'getGlobalOI',
    });
    console.log(`✓ globalOI: ${globalOI.toString()} (${Number(globalOI) / 1e6} USDT)`);

    console.log('\n=== Testing multicall...');

    // Test multicall
    const multicallResult = await client.multicall({
      contracts: [
        {
          address: contracts.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalAssets',
        },
        {
          address: contracts.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalSupply',
        },
        {
          address: contracts.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'convertToAssets',
          args: [WAD],
        },
        {
          address: contracts.oiLimits,
          abi: OI_LIMITS_ABI,
          functionName: 'getGlobalOI',
        }
      ]
    });

    console.log('\n✓ Multicall results:');
    multicallResult.forEach((result, index) => {
      const names = ['totalAssets', 'totalSupply', 'sharePrice', 'globalOI'];
      console.log(`  ${names[index]}: status=${result.status}, result=${result.result?.toString()}`);
    });

    // Test calculations
    console.log('\n=== Testing calculations...');

    const assetFloat = Number(totalAssets) / 1e6;
    const supplyFloat = Number(totalSupply) / 1e18;
    const calcSharePrice = supplyFloat > 0 ? assetFloat / supplyFloat : 1.0;
    const utilization = assetFloat > 0 ? (Number(globalOI) / 1e6) / assetFloat * 100 : 0;

    console.log(`TVL: $${assetFloat.toLocaleString()}`);
    console.log(`Total Shares: ${supplyFloat.toLocaleString()}`);
    console.log(`Calculated Share Price: $${calcSharePrice.toFixed(4)}`);
    console.log(`Contract Share Price: $${(Number(sharePrice) / 1e12).toFixed(4)}`);
    console.log(`Utilization: ${utilization.toFixed(1)}%`);

    // Check for NaN
    const values = { assetFloat, supplyFloat, calcSharePrice, utilization };
    const nanCheck = Object.entries(values).filter(([key, value]) => !isFinite(value) || isNaN(value));
    if (nanCheck.length > 0) {
      console.log('\n❌ NaN detected in:', nanCheck);
    } else {
      console.log('\n✅ All calculations are valid numbers');
    }

  } catch (error) {
    console.error('\n❌ Error:', error);
  }
}

testVaultRPC().then(() => {
  console.log('\n=== DEBUG COMPLETE ===');
}).catch(console.error);