#!/bin/bash
# Generate addresses from bot-wallets.json for use in funding
source /home/lever/lever-protocol/control-plane/deploy-env.sh

WALLETS="/home/lever/lever-protocol/control-plane/bot-wallets.json"
ADDRESSES="/home/lever/lever-protocol/control-plane/bot-addresses.json"

echo "{"
python3 -c "
import json, subprocess
wallets = json.load(open('$WALLETS'))
addresses = {}
for name, key in wallets.items():
    result = subprocess.run(['cast', 'wallet', 'address', '--private-key', key], capture_output=True, text=True)
    addr = result.stdout.strip()
    addresses[name] = addr
json.dump(addresses, open('$ADDRESSES', 'w'), indent=2)
print(f'Generated {len(addresses)} addresses')
for name, addr in list(addresses.items())[:5]:
    print(f'  {name}: {addr}')
print(f'  ... and {len(addresses)-5} more')
"
