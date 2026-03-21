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

// Helper: add commas to a number string (handles decimals)
const addCommas = (numStr: string): string => {
  const [intPart, decPart] = numStr.split('.');
  const withCommas = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return decPart !== undefined ? `${withCommas}.${decPart}` : withCommas;
};

// Helper functions
export const formatWad = (value: bigint): string => {
  // Use BigInt division to avoid precision loss, then convert to number
  try {
    const wholePart = value / WAD;
    const remainder = value % WAD;

    // Convert to number safely for display
    const wholeNumber = Number(wholePart);
    const fractionalNumber = Number(remainder) / Number(WAD);

    const num = wholeNumber + fractionalNumber;

    // Check for overflow/underflow
    if (!isFinite(num)) {
      console.warn('formatWad: number overflow for value:', value.toString());
      return addCommas((Number(wholePart)).toFixed(2));
    }

    if (num >= 1000000) {
      return (num / 1000000).toFixed(2) + 'M';
    } else if (num >= 10000) {
      return addCommas(Math.round(num).toString());
    } else if (num >= 100) {
      return addCommas(num.toFixed(0));
    }
    return addCommas(num.toFixed(2));
  } catch (error) {
    console.error('formatWad error for value:', value.toString(), error);
    return '0.00';
  }
};

export const formatUsdt = (value: bigint): string => {
  // Use BigInt division to avoid precision loss, then convert to number
  try {
    const wholePart = value / USDT_SCALE;
    const remainder = value % USDT_SCALE;

    // Convert to number safely for display
    const wholeNumber = Number(wholePart);
    const fractionalNumber = Number(remainder) / Number(USDT_SCALE);

    const num = wholeNumber + fractionalNumber;

    // Check for overflow/underflow
    if (!isFinite(num)) {
      console.warn('formatUsdt: number overflow for value:', value.toString());
      return addCommas((Number(wholePart)).toFixed(2));
    }

    // Clean display: no cents for large numbers, K/M suffixes
    if (num >= 1000000) {
      return (num / 1000000).toFixed(2) + 'M';
    } else if (num >= 10000) {
      return addCommas(Math.round(num).toString());
    } else if (num >= 100) {
      return addCommas(num.toFixed(0));
    }
    return addCommas(num.toFixed(2));
  } catch (error) {
    console.error('formatUsdt error for value:', value.toString(), error);
    return '0.00';
  }
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
  oiLimitsNew: `0x${string}`;  // New OILimits with correct TVL for cap display
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
  usdt: "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E" as `0x${string}`,
  marketRegistry: "0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7" as `0x${string}`,
  oracleAdapter: "0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c" as `0x${string}`,
  accountManager: "0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684" as `0x${string}`,
  positionManager: "0x25ba54a7b2fBac753B601Da05e3661F2E959510b" as `0x${string}`,

  // Pool contracts
  leverVault: "0x797E10F9F6BD7C725Fc8AD20A5e3330B1BF17360" as `0x${string}`,
  rewardsDistributor: "0xfefbeb90e73ea4652bc41555f764142944aa297d" as `0x${string}`,
  insuranceFund: "0x9173c92d6c4915183c65120bce57cc35e58417c9" as `0x${string}`,
  feeRouter: "0x18f7645a2260e9d874b5e848608f3d3f606fa150" as `0x${string}`,

  // Engine contracts
  leverageModel: "0x5c8a7016ab48484ea2704cd1abbe25fd23c27688" as `0x${string}`,
  oiLimits: "0x905fe91236385733fb92f2f8af6300b0078e6f72" as `0x${string}`,
  oiLimitsNew: "0x905fe91236385733fb92f2f8af6300b0078e6f72" as `0x${string}`,
  borrowFeeEngine: "0x3288aefbd75249fe0bd3834758976b80f9799b21" as `0x${string}`,
  fundingRateEngine: "0xed3e8868da5994ce7a128a4a8a88ab322daf4c00" as `0x${string}`,
  marginEngine: "0x0e0318f93f9657755b63f4b43b32ebfeb17783bc" as `0x${string}`,
  executionEngine: "0x31078bfe85d3f586edce8f5579d32448cb0586d6" as `0x${string}`,
  liquidationEngine: "0x3ccb33b6b7ec00682f5db0245e5d9af6b71fbd47" as `0x${string}`,
  settlementEngine: "0x8dc424200580bc22d8e4de8e77e42884226e5893" as `0x${string}`
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
      oiLimitsNew: (enginesDeployment.oiLimits || "0x905fe91236385733fb92f2f8af6300b0078e6f72") as `0x${string}`,
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