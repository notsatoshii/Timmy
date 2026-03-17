#!/bin/bash
# Fund all seeder wallets with ETH and USDT
source /home/lever/lever-protocol/control-plane/deploy-env.sh
DEPLOYER_KEY=$(cat /home/lever/lever-protocol/.env.deployer)

WALLETS_FILE="/home/lever/lever-protocol/scripts/seeder-wallets.json"
LOG="/home/lever/lever-protocol/control-plane/dispatcher-logs/fund-wallets.log"

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG"; }

# Extract wallet keys
KEYS=$(python3 -c "import json; data=json.load(open('$WALLETS_FILE')); [print(k) for k in data['wallets']]")

i=0
for KEY in $KEYS; do
    i=$((i+1))
    ADDR=$(cast wallet address --private-key "0x$KEY" 2>/dev/null)
    log "Wallet $i: $ADDR"

    # Send 0.001 ETH for gas
    cast send "$ADDR" --value 1000000000000000 --private-key "$DEPLOYER_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 2

    # Mint 1M USDT
    cast send 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E "mint(address,uint256)" "$ADDR" 1000000000000 --private-key "$DEPLOYER_KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 2

    # Approve AccountManager
    cast send 0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E "approve(address,uint256)" 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684 115792089237316195423570985008687907853269984665640564039457584007913129639935 --private-key "0x$KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 2

    # Deposit 500K USDT to AccountManager
    cast send 0x6D2231BB7E8704C1e76de63A06A16d9B59bA6684 "deposit(uint256)" 500000000000 --private-key "0x$KEY" --rpc-url "$RPC_URL" 2>/dev/null
    sleep 2

    log "  Funded wallet $i: $ADDR"
done

log "All $i wallets funded."
