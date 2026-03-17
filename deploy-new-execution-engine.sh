#!/bin/bash

# Deploy new ExecutionEngine with fixed LeverageModel using cast
source control-plane/deploy-env.sh
export PATH="$HOME/.foundry/bin:$PATH"

echo "=== Deploying ExecutionEngine with Fixed LeverageModel ==="
echo "Using LeverageModel: $LEVERAGE_MODEL"

# Constructor parameters for ExecutionEngine
POSITION_MANAGER="0x25ba54a7b2fBac753B601Da05e3661F2E959510b"
OI_LIMITS="0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd"
MARGIN_ENGINE="0xd4e840487bFE3Ca7448BcdB41a7972DfA29B6fce"
ORACLE_ADAPTER="0xf0698FCEDD3A212c5f1D78f7c4c008CB90efeA9c"
MARKET_REGISTRY="0x3Cc9E89DF048CE26Be380696E86814bEbB984DB7"
FEE_ROUTER="0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F"
BORROW_FEE_ENGINE="0x706578de003912C71e534949d8b8DDd5108950e1"
FUNDING_RATE_ENGINE="0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe"
ACCOUNT_MANAGER="0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684"
LEVER_VAULT="0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921"

echo "Current nonce: $(cast nonce $DEPLOYER --rpc-url $RPC_URL)"

# Get the bytecode for ExecutionEngine (we need to find the compiled contract)
echo "Looking for compiled ExecutionEngine..."
find . -name "*.json" -path "*/out/*" | grep ExecutionEngine | head -1