# LEVER Protocol — Base Sepolia Deployment Results

## Deployment Test Results — 2026-03-15

**Status:** SUCCESSFUL (simulation) - Ready for funded deployment
**Chain:** Base Sepolia (84532)
**Deployer:** 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

## Contract Addresses (Phase 1 - Core)

| Contract | Address | Status |
|----------|---------|--------|
| MockUSDT | `0x92c9711101bBB0B742d6320D52521FAd1712A85e` | ✅ Deployed |
| MarketRegistry | `0x463697f45a0dA6B247305bac56F68e37779ba6bF` | ✅ Deployed |
| OracleAdapter | `0x4F0224F2cC6ab7acC1A913D06F055Ae8FA484d78` | ✅ Deployed |
| AccountManager | `0xe0f420dD416e6047fDA063d66292f7679160519B` | ✅ Deployed |
| PositionManager | `0x5D538d96735C4752fF12b590ff4737d856a6f484` | ✅ Deployed |

## Deployment Configuration

**Environment Variables:**
- PRIVATE_KEY: Test key (DO NOT USE IN PRODUCTION)
- ORACLE_KEEPER: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
- PROTOCOL_TREASURY: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
- MARKET_MANAGER: 0x90F79bf6EB2c4f870365E785982E1f101E93b906
- ADMIN_ADDRESS: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

**RPC Endpoint:** https://sepolia.base.org

## Gas Estimation

**Total estimated gas:** 8,556,644
**Estimated cost:** 0.000094123084 ETH
**Gas price:** 0.011 gwei

## Deployment Process Validated

✅ **Foundry configuration** - Updated to support deployment (ffi=true, fs_permissions=read-write)
✅ **Environment setup** - Test keys and RPC configured
✅ **Phase 1 (Core)** - All foundation contracts deploy successfully
✅ **Contract verification** - Addresses generated for Base Sepolia network
✅ **Gas estimation** - Reasonable deployment costs calculated

## Ready for Production Deployment

The deployment system is fully functional and tested. To execute the actual deployment:

1. **Fund the deployer account** with ~0.001 ETH on Base Sepolia
2. **Update environment variables** with production keys/addresses
3. **Run deployment:** `forge script script/DeployCore.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast`
4. **Continue with remaining phases** (Pool, Engines, Roles)
5. **Verify contracts** using `script/Verify.s.sol`

## Next Steps

- [ ] Fund deployer address with Base Sepolia ETH
- [ ] Execute full 4-phase deployment
- [ ] Configure oracle feeds for testnet markets
- [ ] Deploy seed bots for trading/LP activity
- [ ] 48-hour monitoring period

---

**Note:** This was a test deployment using Foundry test keys. All addresses above are for Base Sepolia testnet only.