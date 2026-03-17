const { createPublicClient, http } = require('viem');
const { baseSepolia } = require('viem/chains');

// Set up the same RPC client as frontend
const client = createPublicClient({
  chain: baseSepolia,
  transport: http(),
});

// Contract addresses
const LEVER_VAULT = "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921";
const OI_LIMITS = "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd";
const USDT = "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E";

// Simple ABI for testing
const LEVER_VAULT_ABI = [
  {
    inputs: [],
    name: "totalAssets",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "shares", type: "uint256" }],
    name: "convertToAssets",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  }
];

const OI_LIMITS_ABI = [
  {
    inputs: [],
    name: "getGlobalOI",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  }
];

async function testVaultCalls() {
  console.log("=== Testing Vault RPC Calls ===");

  try {
    // Test individual calls first
    console.log("\n1. Testing totalAssets...");
    const totalAssets = await client.readContract({
      address: LEVER_VAULT,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalAssets',
    });
    console.log("totalAssets:", totalAssets.toString());

    console.log("\n2. Testing totalSupply...");
    const totalSupply = await client.readContract({
      address: LEVER_VAULT,
      abi: LEVER_VAULT_ABI,
      functionName: 'totalSupply',
    });
    console.log("totalSupply:", totalSupply.toString());

    console.log("\n3. Testing convertToAssets...");
    const sharePrice = await client.readContract({
      address: LEVER_VAULT,
      abi: LEVER_VAULT_ABI,
      functionName: 'convertToAssets',
      args: [BigInt('1000000000000000000')], // 1 WAD
    });
    console.log("sharePrice (convertToAssets):", sharePrice.toString());

    console.log("\n4. Testing globalOI...");
    const globalOI = await client.readContract({
      address: OI_LIMITS,
      abi: OI_LIMITS_ABI,
      functionName: 'getGlobalOI',
    });
    console.log("globalOI:", globalOI.toString());

    // Test multicall
    console.log("\n5. Testing multicall...");
    const multicallResult = await client.multicall({
      contracts: [
        {
          address: LEVER_VAULT,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalAssets',
        },
        {
          address: LEVER_VAULT,
          abi: LEVER_VAULT_ABI,
          functionName: 'totalSupply',
        },
        {
          address: LEVER_VAULT,
          abi: LEVER_VAULT_ABI,
          functionName: 'convertToAssets',
          args: [BigInt('1000000000000000000')],
        },
        {
          address: OI_LIMITS,
          abi: OI_LIMITS_ABI,
          functionName: 'getGlobalOI',
        }
      ],
    });

    console.log("\nMulticall results:");
    multicallResult.forEach((result, index) => {
      console.log(`  [${index}] status: ${result.status}, result: ${result.status === 'success' ? result.result?.toString() : result.error?.message}`);
    });

    console.log("\n=== All tests completed successfully ===");

  } catch (error) {
    console.error("RPC test failed:", error);
    console.error("Error details:", {
      message: error.message,
      code: error.code,
      cause: error.cause,
    });
  }
}

testVaultCalls();