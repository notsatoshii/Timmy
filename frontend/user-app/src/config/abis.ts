// Simplified ABIs for the main contract functions needed by the frontend

export const MARKET_REGISTRY_ABI = [
  {
    "inputs": [],
    "name": "getActiveMarkets",
    "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "bytes32", "name": "marketId", "type": "bytes32"}],
    "name": "getMarketInfo",
    "outputs": [
      {"internalType": "string", "name": "description", "type": "string"},
      {"internalType": "uint256", "name": "resolutionTime", "type": "uint256"},
      {"internalType": "bool", "name": "isLive", "type": "bool"},
      {"internalType": "uint8", "name": "category", "type": "uint8"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

export const ORACLE_ADAPTER_ABI = [
  {
    "inputs": [{"internalType": "bytes32", "name": "marketId", "type": "bytes32"}],
    "name": "getPI",
    "outputs": [{"internalType": "uint256", "name": "pi", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

export const EXECUTION_ENGINE_ABI = [
  {
    "inputs": [
      {"internalType": "bytes32", "name": "marketId", "type": "bytes32"},
      {"internalType": "bool", "name": "isLong", "type": "bool"},
      {"internalType": "uint256", "name": "collateralAmount", "type": "uint256"},
      {"internalType": "uint256", "name": "leverage", "type": "uint256"}
    ],
    "name": "openPosition",
    "outputs": [{"internalType": "bytes32", "name": "positionId", "type": "bytes32"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "bytes32", "name": "positionId", "type": "bytes32"},
      {"internalType": "uint256", "name": "collateralToRemove", "type": "uint256"}
    ],
    "name": "closePosition",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const;

export const POSITION_MANAGER_ABI = [
  {
    "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
    "name": "getUserPositions",
    "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "bytes32", "name": "positionId", "type": "bytes32"}],
    "name": "getPosition",
    "outputs": [
      {"internalType": "bytes32", "name": "marketId", "type": "bytes32"},
      {"internalType": "address", "name": "user", "type": "address"},
      {"internalType": "bool", "name": "isLong", "type": "bool"},
      {"internalType": "uint256", "name": "collateralAmount", "type": "uint256"},
      {"internalType": "uint256", "name": "positionSize", "type": "uint256"},
      {"internalType": "uint256", "name": "entryPrice", "type": "uint256"},
      {"internalType": "uint256", "name": "leverage", "type": "uint256"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

export const ACCOUNT_MANAGER_ABI = [
  {
    "inputs": [{"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "deposit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
    "name": "getBalance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

export const LEVER_VAULT_ABI = [
  {
    "inputs": [{"internalType": "uint256", "name": "assets", "type": "uint256"}],
    "name": "deposit",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "shares", "type": "uint256"}],
    "name": "requestWithdrawal",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
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
    "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

export const USDT_ABI = [
  {
    "inputs": [{"internalType": "address", "name": "spender", "type": "address"}, {"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "approve",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "owner", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "owner", "type": "address"}, {"internalType": "address", "name": "spender", "type": "address"}],
    "name": "allowance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "faucet",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const;