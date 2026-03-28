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
export LEVER_VAULT=0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921
export REWARDS_DISTRIBUTOR=0xab8DFA8cF72b054c356961026F8648dB7D860Cb0
export INSURANCE_FUND=0xfdd5e050bef5ae4861b091b9701e2e7a4a30bcea
export FEE_ROUTER=0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F

# Engine contracts — AUDIT FIX DEPLOYMENT 2026-03-26
export LEVERAGE_MODEL=0xE89f4835C3075E9f1e599786A232a00c1E61833B
export OI_LIMITS=0xE336dDfCF31a0274D3DEa317Fb8d8BBad4E13758
export BORROW_FEE_ENGINE=0x706578de003912C71e534949d8b8DDd5108950e1
export FUNDING_RATE_ENGINE=0xf96b5dba5763be3521df0a445e8b4e12db59baac
export MARGIN_ENGINE=0xedcd246c7c0bef806df1ce9b4655cfe6ee7353d5
export EXECUTION_ENGINE=0xE91C216b2baAeb4b088A1531469234A2C5b5fDc2
export LIQUIDATION_ENGINE=0x0756a2a91dd62ce8982c652d504dd76a2ddae5ac
export SETTLEMENT_ENGINE=0xd430c69184aeca515a1e1fd4a3fa2a9fd65532c2
