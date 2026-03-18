// Test script to simulate ProtocolStats contract calls and see what values are returned
const { createPublicClient, http } = require('viem');
const { baseSepolia } = require('viem/chains');

// Contract addresses (from frontend config)
const addresses = {
  leverVault: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921",
  oiLimits: "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd",
  insuranceFund: "0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8",
  borrowFeeEngine: "0x706578de003912C71e534949d8b8DDd5108950e1"
};

// Create client
const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http()
});

// Minimal ABIs for the functions we need
const leverVaultABI = [
  {
    "name": "totalAssets",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}]
  }
];

const oiLimitsABI = [
  {
    "name": "getGlobalOI",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}]
  }
];

const insuranceFundABI = [
  {
    "name": "getBalance",
    "type": "function",
    "stateMutability": "view",
    "inputs": [],
    "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}]
  }
];

const borrowFeeEngineABI = [
  {
    "name": "getCurrentBorrowRate",
    "type": "function",
    "stateMutability": "view",
    "inputs": [
      {"name": "marketId", "type": "bytes32", "internalType": "bytes32"},
      {"name": "isLong", "type": "bool", "internalType": "bool"}
    ],
    "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}]
  }
];

// Formatting functions
const USDT_SCALE = BigInt('1000000'); // 1e6
const WAD = BigInt('1000000000000000000'); // 1e18

const formatUsdt = (value) => {
  try {
    const wholePart = value / USDT_SCALE;
    const remainder = value % USDT_SCALE;
    const wholeNumber = Number(wholePart);
    const fractionalNumber = Number(remainder) / Number(USDT_SCALE);
    const num = wholeNumber + fractionalNumber;
    return num.toFixed(2);
  } catch (error) {
    console.error('formatUsdt error:', error);
    return '0.00';
  }
};

const formatWad = (value) => {
  try {
    const wholePart = value / WAD;
    const remainder = value % WAD;
    const wholeNumber = Number(wholePart);
    const fractionalNumber = Number(remainder) / Number(WAD);
    const num = wholeNumber + fractionalNumber;
    return num.toFixed(2);
  } catch (error) {
    console.error('formatWad error:', error);
    return '0.00';
  }
};

async function testProtocolStats() {
  console.log('=== Testing Protocol Stats Contract Calls ===\n');

  try {
    // Test TVL from LeverVault.totalAssets()
    console.log('1. Testing TVL (LeverVault.totalAssets)...');
    try {
      const tvl = await publicClient.readContract({
        address: addresses.leverVault,
        abi: leverVaultABI,
        functionName: 'totalAssets'
      });
      console.log('  Raw TVL:', tvl.toString());
      console.log('  Formatted TVL: $' + formatUsdt(tvl));
    } catch (error) {
      console.error('  TVL Error:', error.message);
    }

    // Test Total OI from OILimits.getGlobalOI()
    console.log('\n2. Testing Total OI (OILimits.getGlobalOI)...');
    try {
      const totalOI = await publicClient.readContract({
        address: addresses.oiLimits,
        abi: oiLimitsABI,
        functionName: 'getGlobalOI'
      });
      console.log('  Raw Total OI:', totalOI.toString());
      console.log('  Formatted Total OI: $' + formatUsdt(totalOI));
    } catch (error) {
      console.error('  Total OI Error:', error.message);
    }

    // Test Insurance Fund from InsuranceFund.getBalance()
    console.log('\n3. Testing Insurance Fund (InsuranceFund.getBalance)...');
    try {
      const insurance = await publicClient.readContract({
        address: addresses.insuranceFund,
        abi: insuranceFundABI,
        functionName: 'getBalance'
      });
      console.log('  Raw Insurance:', insurance.toString());
      console.log('  Formatted Insurance (WAD): $' + formatWad(insurance));
      console.log('  Formatted Insurance (USDT): $' + formatUsdt(insurance));
    } catch (error) {
      console.error('  Insurance Error:', error.message);
    }

    // Test Borrow Rate from BorrowFeeEngine.getCurrentBorrowRate()
    console.log('\n4. Testing Borrow Rate (BorrowFeeEngine.getCurrentBorrowRate)...');
    try {
      const marketId = '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1'; // SpaceX market
      const borrowRate = await publicClient.readContract({
        address: addresses.borrowFeeEngine,
        abi: borrowFeeEngineABI,
        functionName: 'getCurrentBorrowRate',
        args: [marketId, true]
      });
      console.log('  Raw Borrow Rate:', borrowRate.toString());
      console.log('  Formatted Borrow Rate (WAD):', formatWad(borrowRate));
    } catch (error) {
      console.error('  Borrow Rate Error:', error.message);
    }

    console.log('\n=== Test Complete ===');

  } catch (error) {
    console.error('Overall test error:', error);
  }
}

testProtocolStats();