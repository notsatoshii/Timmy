#!/usr/bin/env python3

import json
import subprocess
import os

# Load environment variables
os.system("source control-plane/deploy-env.sh")

# Get environment variables
RPC_URL = "https://sepolia.base.org"
INSURANCE_FUND = "0x39Aca7F8CbB4b054C2f6aaD637a61942898B1Ae8"
FEE_ROUTER = "0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F"

def run_cast_command(cmd):
    """Run a cast command and return the result"""
    full_cmd = f'PATH="/home/lever/.foundry/bin:$PATH" && {cmd}'
    result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip(), result.stderr.strip()

def hex_to_decimal(hex_val):
    """Convert hex to decimal"""
    if hex_val.startswith('0x'):
        return int(hex_val, 16)
    return int(hex_val)

def wei_to_ether(wei_val):
    """Convert wei to ether units"""
    return wei_val / (10**18)

print("=== Insurance Fund Debug Report ===\n")

# Get Insurance Fund balance
print("1. Current Insurance Fund Balance:")
balance_hex, err = run_cast_command(f'cast call {INSURANCE_FUND} "getBalance()" --rpc-url {RPC_URL}')
if err:
    print(f"Error: {err}")
else:
    balance_wei = hex_to_decimal(balance_hex)
    balance_usdt = wei_to_ether(balance_wei)
    print(f"   Balance: {balance_usdt:.6f} USDT")

print("\n2. Insurance Fund Ratio (IFR):")
ifr_hex, err = run_cast_command(f'cast call {INSURANCE_FUND} "getIFR()" --rpc-url {RPC_URL}')
if err:
    print(f"Error: {err}")
else:
    ifr_wei = hex_to_decimal(ifr_hex)
    ifr = wei_to_ether(ifr_wei)
    print(f"   IFR: {ifr:.6f} ({ifr*100:.2f}%)")

print("\n3. Current Fee Router Tier:")
tier_hex, err = run_cast_command(f'cast call {FEE_ROUTER} "getCurrentTier()" --rpc-url {RPC_URL}')
if err:
    print(f"Error: {err}")
else:
    tier = hex_to_decimal(tier_hex)
    print(f"   Tier: {tier} ({'50/50/0 LP/Protocol/Insurance' if tier == 2 else '50/30/20 LP/Protocol/Insurance'})")

print("\n4. Total Fees Routed by Type:")
fee_types = ["BORROW", "TRANSACTION", "LIQUIDATION", "SETTLEMENT"]
for i, fee_type in enumerate(fee_types):
    fees_hex, err = run_cast_command(f'cast call {FEE_ROUTER} "getTotalFeesRouted(uint8)" {i} --rpc-url {RPC_URL}')
    if err:
        print(f"   {fee_type}: Error - {err}")
    else:
        fees_wei = hex_to_decimal(fees_hex)
        fees_usdt = wei_to_ether(fees_wei)
        print(f"   {fee_type}: {fees_usdt:.6f} USDT")

print("\n5. LeverVault TVL:")
tvl_hex, err = run_cast_command(f'cast call 0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921 "totalAssets()" --rpc-url {RPC_URL}')
if err:
    print(f"Error: {err}")
else:
    tvl_wei = hex_to_decimal(tvl_hex)
    tvl_usdt = wei_to_ether(tvl_wei)
    print(f"   TVL: {tvl_usdt:.6f} USDT")

print("\n=== Analysis ===")
if balance_usdt > 10000 and tvl_usdt < 1:
    print("ISSUE IDENTIFIED:")
    print("- Insurance Fund has significant balance (~$5M) far exceeding the $10K bootstrap")
    print("- TVL is near zero, causing extremely high IFR")
    print("- System is in Tier 2, so no new fees go to Insurance Fund (working as designed)")
    print("- Need to investigate how Insurance Fund got this balance")
else:
    print("No obvious issues detected")