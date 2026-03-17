// Test vault data with Node.js
const { createPublicClient, http } = require('viem');

const client = createPublicClient({
  chain: {
    id: 84532,
    name: 'Base Sepolia',
    nativeCurrency: { decimals: 18, name: 'Ether', symbol: 'ETH' },
    rpcUrls: {
      default: { http: ['https://sepolia.base.org'] }
    }
  },
  transport: http('https://sepolia.base.org')
});

const LEVER_VAULT_ADDRESS = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';
const OI_LIMITS_ADDRESS = '0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd';

// Basic ABI
const VAULT_ABI = [
  { "inputs": [], "name": "totalAssets", "outputs": [{"type": "uint256"}], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "totalSupply", "outputs": [{"type": "uint256"}], "stateMutability": "view", "type": "function" },
  { "inputs": [{"type": "uint256"}], "name": "convertToAssets", "outputs": [{"type": "uint256"}], "stateMutability": "view", "type": "function" }
];

const OI_ABI = [
  { "inputs": [], "name": "getGlobalOI", "outputs": [{"type": "uint256"}], "stateMutability": "view", "type": "function" }
];

async function test() {
  try {
    console.log('Testing vault contracts...');

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

    const sharePrice = await client.readContract({
      address: LEVER_VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: 'convertToAssets',
      args: [BigInt('1000000000000000000')] // 1 WAD
    });
    console.log('Share Price:', sharePrice.toString());

    const globalOI = await client.readContract({
      address: OI_LIMITS_ADDRESS,
      abi: OI_ABI,
      functionName: 'getGlobalOI'
    });
    console.log('Global OI:', globalOI.toString());

    // Calculate readable values
    const tvl = Number(totalAssets) / 1e6; // USDT has 6 decimals
    const sharePriceReadable = Number(sharePrice) / 1e6; // Convert to USDT
    console.log('TVL: $' + tvl.toLocaleString());
    console.log('Share Price: $' + sharePriceReadable.toFixed(4));

  } catch (error) {
    console.error('Error:', error.message);
  }
}

test();