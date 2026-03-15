// Dynamic contract address configuration that reads from deployment JSONs
// This replaces hardcoded addresses with runtime loading from deployment files

// Chain configuration
export const BASE_SEPOLIA_CHAIN_ID = 84532;

export const CHAIN_CONFIG = {
  id: BASE_SEPOLIA_CHAIN_ID,
  name: 'Base Sepolia',
  network: 'base-sepolia',
  nativeCurrency: {
    decimals: 18,
    name: 'Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    public: { http: ['https://sepolia.base.org'] },
    default: { http: ['https://sepolia.base.org'] },
  },
  blockExplorers: {
    etherscan: { name: 'BaseScan', url: 'https://sepolia.basescan.org' },
    default: { name: 'BaseScan', url: 'https://sepolia.basescan.org' },
  },
  testnet: true,
};

// Constants
export const WAD = BigInt('1000000000000000000'); // 1e18
export const USDT_DECIMALS = 6;
export const USDT_SCALE = BigInt('1000000'); // 1e6

// Helper functions
export const formatWad = (value: bigint): string => {
  return (Number(value) / Number(WAD)).toFixed(2);
};

export const formatUsdt = (value: bigint): string => {
  return (Number(value) / Number(USDT_SCALE)).toFixed(2);
};

export const parseUsdt = (value: string): bigint => {
  return BigInt(Math.floor(parseFloat(value) * Number(USDT_SCALE)));
};

export const parseWad = (value: string): bigint => {
  return BigInt(Math.floor(parseFloat(value) * Number(WAD)));
};

// Contract addresses type definition
export interface ContractAddresses {
  // Core contracts
  usdt: `0x${string}`;
  marketRegistry: `0x${string}`;
  oracleAdapter: `0x${string}`;
  accountManager: `0x${string}`;
  positionManager: `0x${string}`;

  // Pool contracts
  leverVault: `0x${string}`;
  rewardsDistributor: `0x${string}`;
  insuranceFund: `0x${string}`;
  feeRouter: `0x${string}`;

  // Engine contracts
  leverageModel: `0x${string}`;
  oiLimits: `0x${string}`;
  borrowFeeEngine: `0x${string}`;
  fundingRateEngine: `0x${string}`;
  marginEngine: `0x${string}`;
  executionEngine: `0x${string}`;
  liquidationEngine: `0x${string}`;
  settlementEngine: `0x${string}`;
}

// Cached contract addresses
let cachedAddresses: ContractAddresses | null = null;

// Fallback addresses (current deployment for development)
const FALLBACK_ADDRESSES: ContractAddresses = {
  // Core contracts
  usdt: "0x92c9711101bBB0B742d6320D52521FAd1712A85e" as `0x${string}`,
  marketRegistry: "0x463697f45a0dA6B247305bac56F68e37779ba6bF" as `0x${string}`,
  oracleAdapter: "0x4F0224F2cC6ab7acC1A913D06F055Ae8FA484d78" as `0x${string}`,
  accountManager: "0xe0f420dD416e6047fDA063d66292f7679160519B" as `0x${string}`,
  positionManager: "0x5D538d96735C4752fF12b590ff4737d856a6f484" as `0x${string}`,

  // Pool contracts
  leverVault: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as `0x${string}`,
  rewardsDistributor: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" as `0x${string}`,
  insuranceFund: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9" as `0x${string}`,
  feeRouter: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9" as `0x${string}`,

  // Engine contracts
  leverageModel: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as `0x${string}`,
  oiLimits: "0x5FbDB2315678afecb367f032d93F642f64180aa3" as `0x${string}`,
  borrowFeeEngine: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" as `0x${string}`,
  fundingRateEngine: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9" as `0x${string}`,
  marginEngine: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9" as `0x${string}`,
  executionEngine: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707" as `0x${string}`,
  liquidationEngine: "0x0165878A594ca255338adfa4d48449f69242Eb8F" as `0x${string}`,
  settlementEngine: "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853" as `0x${string}`
};

/**
 * Load contract addresses from deployment JSON files
 * Falls back to hardcoded addresses if fetch fails
 */
export async function loadContractAddresses(): Promise<ContractAddresses> {
  if (cachedAddresses) {
    return cachedAddresses;
  }

  try {
    // Fetch all three deployment files in parallel
    const [coreResponse, poolResponse, enginesResponse] = await Promise.all([
      fetch('/deployments/core-deployment.json'),
      fetch('/deployments/pool-deployment.json'),
      fetch('/deployments/engines-deployment.json')
    ]);

    if (!coreResponse.ok || !poolResponse.ok || !enginesResponse.ok) {
      console.warn('Failed to fetch one or more deployment files, using fallback addresses');
      cachedAddresses = FALLBACK_ADDRESSES;
      return cachedAddresses;
    }

    const [coreDeployment, poolDeployment, enginesDeployment] = await Promise.all([
      coreResponse.json(),
      poolResponse.json(),
      enginesResponse.json()
    ]);

    // Combine all deployments into a single ContractAddresses object
    cachedAddresses = {
      // Core contracts
      usdt: coreDeployment.usdt as `0x${string}`,
      marketRegistry: coreDeployment.marketRegistry as `0x${string}`,
      oracleAdapter: coreDeployment.oracleAdapter as `0x${string}`,
      accountManager: coreDeployment.accountManager as `0x${string}`,
      positionManager: coreDeployment.positionManager as `0x${string}`,

      // Pool contracts
      leverVault: poolDeployment.leverVault as `0x${string}`,
      rewardsDistributor: poolDeployment.rewardsDistributor as `0x${string}`,
      insuranceFund: poolDeployment.insuranceFund as `0x${string}`,
      feeRouter: poolDeployment.feeRouter as `0x${string}`,

      // Engine contracts
      leverageModel: enginesDeployment.leverageModel as `0x${string}`,
      oiLimits: enginesDeployment.oiLimits as `0x${string}`,
      borrowFeeEngine: enginesDeployment.borrowFeeEngine as `0x${string}`,
      fundingRateEngine: enginesDeployment.fundingRateEngine as `0x${string}`,
      marginEngine: enginesDeployment.marginEngine as `0x${string}`,
      executionEngine: enginesDeployment.executionEngine as `0x${string}`,
      liquidationEngine: enginesDeployment.liquidationEngine as `0x${string}`,
      settlementEngine: enginesDeployment.settlementEngine as `0x${string}`
    };

    console.log('Contract addresses loaded from deployment files');
    return cachedAddresses;

  } catch (error) {
    console.error('Error loading contract addresses:', error);
    console.warn('Using fallback addresses');
    cachedAddresses = FALLBACK_ADDRESSES;
    return cachedAddresses;
  }
}

/**
 * Get contract addresses synchronously (returns fallback if not loaded)
 * Use loadContractAddresses() for async loading with proper error handling
 */
export function getContractAddresses(): ContractAddresses {
  return cachedAddresses || FALLBACK_ADDRESSES;
}

/**
 * Clear cached addresses (useful for testing or redeployment)
 */
export function clearAddressCache(): void {
  cachedAddresses = null;
}

// Export fallback for immediate use (deprecated - use loadContractAddresses)
export const CONTRACT_ADDRESSES = FALLBACK_ADDRESSES;