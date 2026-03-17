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
export INSURANCE_FUND=0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8
export FEE_ROUTER=0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F

# Engine contracts
export LEVERAGE_MODEL=0xf649e342673C3e86c18Bf30C4163ec9d7090F9EF
export OI_LIMITS=0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd
export BORROW_FEE_ENGINE=0x706578de003912C71e534949d8b8DDd5108950e1
export FUNDING_RATE_ENGINE=0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
export MARGIN_ENGINE=0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce
export EXECUTION_ENGINE=0x353DbFFD7f936A0bb4390339f33bf2e3AB3C4e9D
export LIQUIDATION_ENGINE=0x2A42Ef441CAbF34D3Ff9B9867CAf4Ae087FEC42E
export SETTLEMENT_ENGINE=0x9c7E9496A25Bf06f163A4483e5702ac350e8e9aD
