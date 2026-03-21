# COMPLETE ROLE GRANTS — After Full Redeploy

All role hashes and exact grant commands for every contract interaction.

---

## ROLE HASH REFERENCE

```
ENGINE_ROLE (PM, AM, OILimits, BFE, FRE, ME):
  keccak256("ENGINE") = 0x5d0c23b505d97686a7eb149c2db3c9cdda71d0f1778515d411985ce042bf17a1

KEEPER_ROLE (BFE, FRE, LM):
  keccak256("KEEPER_ROLE") = 0xfc8737ab85eb45125971625a9ebdb75cc78e01d5c1fa80c4c6e5203f47bc4fab

EXECUTION_ENGINE_ROLE (LeverVault, FeeRouter):
  keccak256("EXECUTION_ENGINE_ROLE") = 0xe84f0c4192c51045392aba129d576dc9b52e35669b1a5350f3980991c51559ea

LIQUIDATION_ENGINE_ROLE (LeverVault, FeeRouter, InsuranceFund):
  keccak256("LIQUIDATION_ENGINE_ROLE") = 0x73cc1824a5ac1764c2e141cf3615a9dcb73677c4e5be5154addc88d3e0cc1480

SETTLEMENT_ENGINE_ROLE (FeeRouter, InsuranceFund):
  keccak256("SETTLEMENT_ENGINE_ROLE") = 0x27992f265cf1c47d7bfde3d3fbb9db6bb9a2d81a882e2b3e3e6b12b1a5e6f3c2
  (verify: cast keccak "SETTLEMENT_ENGINE_ROLE")

FEE_ROUTER_ROLE (RewardsDistributor, InsuranceFund):
  keccak256("FEE_ROUTER_ROLE") = 0x554350884353c50d2698f09dbf4f95bc975135433fbaab20190385d97269654b

FUNDING_RATE_ENGINE_ROLE (RewardsDistributor):
  keccak256("FUNDING_RATE_ENGINE_ROLE") = 0xc134843515b78e978ca9d229c055097fee561f4dbb2c3236edcca4f154a594d5

BORROW_FEE_ENGINE_ROLE (FeeRouter):
  keccak256("BORROW_FEE_ENGINE_ROLE") = (compute: cast keccak "BORROW_FEE_ENGINE_ROLE")

LEVER_VAULT_ROLE (RewardsDistributor):
  keccak256("LEVER_VAULT_ROLE") = 0x841b004e375a0fe80a779fed992585abd678b0a1bee3f0469053235a18a78216

ORACLE_ROLE (OracleAdapter):
  keccak256("ORACLE_ROLE") = (compute: cast keccak "ORACLE_ROLE")
```

---

## GRANTS BY TARGET CONTRACT

### PositionManager (kept — uses ENGINE role)
```bash
PM=$POSITION_MANAGER
ENGINE=0x5d0c23b505d97686a7eb149c2db3c9cdda71d0f1778515d411985ce042bf17a1
cast send $PM "grantRole(bytes32,address)" $ENGINE $NEW_EE   # ExecutionEngine
cast send $PM "grantRole(bytes32,address)" $ENGINE $NEW_LE   # LiquidationEngine
cast send $PM "grantRole(bytes32,address)" $ENGINE $NEW_SE   # SettlementEngine
# Also keep DEPLOYER ENGINE role for force-close capability
cast send $PM "grantRole(bytes32,address)" $ENGINE $DEPLOYER
```

### AccountManager (kept — uses ENGINE role)
```bash
AM=$ACCOUNT_MANAGER
cast send $AM "grantRole(bytes32,address)" $ENGINE $NEW_EE
cast send $AM "grantRole(bytes32,address)" $ENGINE $NEW_LE
```

### New OILimits (uses ENGINE role)
```bash
cast send $NEW_OI "grantRole(bytes32,address)" $ENGINE $NEW_EE
cast send $NEW_OI "grantRole(bytes32,address)" $ENGINE $NEW_LE
cast send $NEW_OI "grantRole(bytes32,address)" $ENGINE $NEW_SE
```

### New BorrowFeeEngine (uses ENGINE + KEEPER)
```bash
cast send $NEW_BFE "grantRole(bytes32,address)" $ENGINE $NEW_EE
cast send $NEW_BFE "grantRole(bytes32,address)" $KEEPER $DEPLOYER  # for accrueAll via keeper
```

### New FundingRateEngine (uses ENGINE + KEEPER)
```bash
cast send $NEW_FRE "grantRole(bytes32,address)" $ENGINE $NEW_EE
cast send $NEW_FRE "grantRole(bytes32,address)" $KEEPER $DEPLOYER  # for accrueFunding via keeper
```

### New MarginEngine (uses ENGINE role)
```bash
cast send $NEW_ME "grantRole(bytes32,address)" $ENGINE $NEW_EE
```

### New LeverVault (uses EXECUTION_ENGINE_ROLE + LIQUIDATION_ENGINE_ROLE)
```bash
EE_ROLE=0xe84f0c4192c51045392aba129d576dc9b52e35669b1a5350f3980991c51559ea
LE_ROLE=0x73cc1824a5ac1764c2e141cf3615a9dcb73677c4e5be5154addc88d3e0cc1480
cast send $NEW_VAULT "grantRole(bytes32,address)" $EE_ROLE $NEW_EE
cast send $NEW_VAULT "grantRole(bytes32,address)" $LE_ROLE $NEW_LE
# Note: SettlementEngine may also need a role — check if SE calls vault
```

### New FeeRouter (uses EXECUTION_ENGINE_ROLE + LIQUIDATION_ENGINE_ROLE + SETTLEMENT_ENGINE_ROLE + BORROW_FEE_ENGINE_ROLE)
```bash
EE_ROLE=0xe84f0c4192c51045392aba129d576dc9b52e35669b1a5350f3980991c51559ea
LE_ROLE=0x73cc1824a5ac1764c2e141cf3615a9dcb73677c4e5be5154addc88d3e0cc1480
SE_ROLE=$(cast keccak "SETTLEMENT_ENGINE_ROLE")
BFE_ROLE=$(cast keccak "BORROW_FEE_ENGINE_ROLE")
cast send $NEW_FR "grantRole(bytes32,address)" $EE_ROLE $NEW_EE
cast send $NEW_FR "grantRole(bytes32,address)" $LE_ROLE $NEW_LE
cast send $NEW_FR "grantRole(bytes32,address)" $SE_ROLE $NEW_SE
cast send $NEW_FR "grantRole(bytes32,address)" $BFE_ROLE $NEW_BFE
```

### New InsuranceFund (uses FEE_ROUTER_ROLE + LIQUIDATION_ENGINE_ROLE + SETTLEMENT_ENGINE_ROLE)
```bash
FR_ROLE=0x554350884353c50d2698f09dbf4f95bc975135433fbaab20190385d97269654b
LE_ROLE=0x73cc1824a5ac1764c2e141cf3615a9dcb73677c4e5be5154addc88d3e0cc1480
SE_ROLE=$(cast keccak "SETTLEMENT_ENGINE_ROLE")
cast send $NEW_IF "grantRole(bytes32,address)" $FR_ROLE $NEW_FR
cast send $NEW_IF "grantRole(bytes32,address)" $LE_ROLE $NEW_LE
cast send $NEW_IF "grantRole(bytes32,address)" $SE_ROLE $NEW_SE
```

### New RewardsDistributor (uses FEE_ROUTER_ROLE + FUNDING_RATE_ENGINE_ROLE + LEVER_VAULT_ROLE)
```bash
FR_ROLE=0x554350884353c50d2698f09dbf4f95bc975135433fbaab20190385d97269654b
FRE_ROLE=0xc134843515b78e978ca9d229c055097fee561f4dbb2c3236edcca4f154a594d5
LV_ROLE=0x841b004e375a0fe80a779fed992585abd678b0a1bee3f0469053235a18a78216
cast send $NEW_RD "grantRole(bytes32,address)" $FR_ROLE $NEW_FR
cast send $NEW_RD "grantRole(bytes32,address)" $FRE_ROLE $NEW_FRE
cast send $NEW_RD "grantRole(bytes32,address)" $LV_ROLE $NEW_VAULT
```

### OracleAdapter (kept — verify ORACLE_ROLE for deployer)
```bash
ORACLE_ROLE=$(cast keccak "ORACLE_ROLE")
# Verify deployer has it:
cast call $ORACLE_ADAPTER "hasRole(bytes32,address)(bool)" $ORACLE_ROLE $DEPLOYER --rpc-url $RPC_URL
# If false, grant it (deployer is DEFAULT_ADMIN):
cast send $ORACLE_ADAPTER "grantRole(bytes32,address)" $ORACLE_ROLE $DEPLOYER
```

**TOTAL: ~30 role grants**

---

## GRANTS VERIFICATION

After all grants, verify each critical path:
```bash
# Can EE write to PM?
cast call $PM "hasRole(bytes32,address)(bool)" $ENGINE $NEW_EE
# Can EE write to OILimits?
cast call $NEW_OI "hasRole(bytes32,address)(bool)" $ENGINE $NEW_EE
# Can EE write to Vault?
cast call $NEW_VAULT "hasRole(bytes32,address)(bool)" $EE_ROLE $NEW_EE
# Can LE liquidate via PM?
cast call $PM "hasRole(bytes32,address)(bool)" $ENGINE $NEW_LE
# Can LE write to Vault?
cast call $NEW_VAULT "hasRole(bytes32,address)(bool)" $LE_ROLE $NEW_LE
# Can FR route to IF?
cast call $NEW_IF "hasRole(bytes32,address)(bool)" $FR_ROLE $NEW_FR
# Can FR route to RD?
cast call $NEW_RD "hasRole(bytes32,address)(bool)" $FR_ROLE $NEW_FR
# Can keeper accrue BFE?
cast call $NEW_BFE "hasRole(bytes32,address)(bool)" $KEEPER $DEPLOYER
# Can keeper accrue FRE?
cast call $NEW_FRE "hasRole(bytes32,address)(bool)" $KEEPER $DEPLOYER
```

ALL must return true. If any is false, the corresponding operation will revert with AccessControlUnauthorizedAccount.
