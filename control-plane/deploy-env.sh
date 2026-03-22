#!/bin/bash
# SINGLE SOURCE OF TRUTH for all LEVER deployment addresses
# Source this before any script: source control-plane/deploy-env.sh

export RPC_URL="https://sepolia.base.org"
export CHAIN_ID=84532

# Read keys from files (don't hardcode keys in this file)
if [ -f /home/lever/lever-protocol/.env.deployer ]; then
    export PRIVATE_KEY=$(cat /home/lever/lever-protocol/.env.deployer | tr -d '[:space:]')
fi
if [ -f /home/lever/lever-protocol/.env.testwallet ]; then
    export TEST_WALLET_KEY=$(cat /home/lever/lever-protocol/.env.testwallet | tr -d '[:space:]')
fi

# Deployer address
export DEPLOYER=0x0e4D636c6D79c380A137f28EF73E054364cd5434

# Core contracts
export USDT_ADDRESS=0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E
export MARKET_REGISTRY=0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7
export ORACLE_ADAPTER=0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c
export ACCOUNT_MANAGER=0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684
export POSITION_MANAGER=0x25ba54a7b2fBac753B601Da05e3661F2E959510b

# Pool contracts
export LEVER_VAULT=0x1b623D8671c417fe5151cCDb38ec7cAB64332836
export REWARDS_DISTRIBUTOR=0xfefbeb90e73ea4652bc41555f764142944aa297d
export INSURANCE_FUND=0x9173c92d6c4915183c65120bce57cc35e58417c9
export FEE_ROUTER=0x18f7645a2260e9d874b5e848608f3d3f606fa150

# Engine contracts
export LEVERAGE_MODEL=0x474E2eE2911544a385eb017369e8516Ad6DcCAbd
export OI_LIMITS=0x905fe91236385733fb92f2f8af6300b0078e6f72
export BORROW_FEE_ENGINE=0x3288aefbd75249fe0bd3834758976b80f9799b21
export FUNDING_RATE_ENGINE=0xed3e8868da5994ce7a128a4a8a88ab322daf4c00
export MARGIN_ENGINE=0x0e0318f93f9657755b63f4b43b32ebfeb17783bc
export EXECUTION_ENGINE=0xafEA713Dc2d6ebec15B21aB92bd15bC733D5B786
export LIQUIDATION_ENGINE=0x0374edd7DCd819548C9dBf53c36f15880FaD69eD
export SETTLEMENT_ENGINE=0xdfB429809e0862e01Dcc73A6621b8729325F5691
