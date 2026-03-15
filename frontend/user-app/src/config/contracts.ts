// Contract addresses for Base Sepolia deployment
export const CONTRACT_ADDRESSES = {
  // Core contracts
  usdt: "0x92c9711101bBB0B742d6320D52521FAd1712A85e",
  marketRegistry: "0x463697f45a0dA6B247305bac56F68e37779ba6bF",
  oracleAdapter: "0x4F0224F2cC6ab7acC1A913D06F055Ae8FA484d78",
  accountManager: "0xe0f420dD416e6047fDA063d66292f7679160519B",
  positionManager: "0x5D538d96735C4752fF12b590ff4737d856a6f484",

  // Pool contracts
  leverVault: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  rewardsDistributor: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  insuranceFund: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
  feeRouter: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",

  // Engine contracts
  leverageModel: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  oiLimits: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
  borrowFeeEngine: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  fundingRateEngine: "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
  marginEngine: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",
  executionEngine: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
  liquidationEngine: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
  settlementEngine: "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853"
} as const;

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