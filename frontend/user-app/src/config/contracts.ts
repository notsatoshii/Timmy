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
  const num = Number(value) / Number(WAD);
  return addCommas(num.toFixed(2));
};

export const formatUsdt = (value: bigint): string => {
  const num = Number(value) / Number(USDT_SCALE);
  return addCommas(num.toFixed(2));
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
  usdt: "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E" as `0x${string}`,
  marketRegistry: "0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7" as `0x${string}`,
  oracleAdapter: "0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c" as `0x${string}`,
  accountManager: "0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684" as `0x${string}`,
  positionManager: "0x25ba54a7b2fBac753B601Da05e3661F2E959510b" as `0x${string}`,

  // Pool contracts
  leverVault: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921" as `0x${string}`,
  rewardsDistributor: "0xab8DFA8cF72b054c356961026F8648dB7D860Cb0" as `0x${string}`,
  insuranceFund: "0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8" as `0x${string}`,
  feeRouter: "0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F" as `0x${string}`,

  // Engine contracts
  leverageModel: "0x63B98Ec1e559E3b24199eb2115F0a57222e9818c" as `0x${string}`,
  oiLimits: "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd" as `0x${string}`,
  borrowFeeEngine: "0x706578de003912C71e534949d8b8DDd5108950e1" as `0x${string}`,
  fundingRateEngine: "0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe" as `0x${string}`,
  marginEngine: "0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce" as `0x${string}`,
  executionEngine: "0x081F77C848EaaCfBfCD06E159C6B8d437db6F386" as `0x${string}`,
  liquidationEngine: "0x2A42Ef441CAbF34D3Ff9B9867CAf4Ae087FEC42E" as `0x${string}`,
  settlementEngine: "0x9c7E9496A25Bf06f163A4483e5702ac350e8e9aD" as `0x${string}`
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