const { ethers } = require('ethers');

// Contract addresses from deploy-env.sh
const INSURANCE_FUND = '0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8';
const FEE_ROUTER = '0x4ad53f14b51C06298DCb0e2fF8f258EF8a31Ea32';
const USDT_ADDRESS = '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E';
const LEVER_VAULT = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';

// RPC URL
const RPC_URL = 'https://sepolia.base.org';

// Minimal ABI for our investigation
const INSURANCE_FUND_ABI = [
  'function getBalance() view returns (uint256)',
  'function getIFR() view returns (uint256)',
  'function isFullyFunded() view returns (bool)',
  'function getTarget() view returns (uint256)',
  'function getFloor() view returns (uint256)',
  'function hasRole(bytes32 role, address account) view returns (bool)'
];

const FEE_ROUTER_ABI = [
  'function getCurrentTier() view returns (uint8)',
  'function getCurrentSplit() view returns (uint256, uint256, uint256)',
  'function getTotalFeesRouted(uint8 feeType) view returns (uint256)',
  'function hasRole(bytes32 role, address account) view returns (bool)'
];

const ERC20_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function decimals() view returns (uint8)'
];

const LEVER_VAULT_ABI = [
  'function totalAssets() view returns (uint256)',
  'function totalSupply() view returns (uint256)'
];

async function investigate() {
  console.log('=== INSURANCE FUND INVESTIGATION ===');
  console.log('Date: 2026-03-18');
  console.log('');

  try {
    const provider = new ethers.JsonRpcProvider(RPC_URL);

    // Connect to contracts
    const insuranceFund = new ethers.Contract(INSURANCE_FUND, INSURANCE_FUND_ABI, provider);
    const feeRouter = new ethers.Contract(FEE_ROUTER, FEE_ROUTER_ABI, provider);
    const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, provider);
    const leverVault = new ethers.Contract(LEVER_VAULT, LEVER_VAULT_ABI, provider);

    // 1. Check Insurance Fund internal balance
    console.log('=== CURRENT STATE ===');
    const internalBalance = await insuranceFund.getBalance();
    console.log(`Insurance Fund Internal Balance: ${ethers.formatEther(internalBalance)} USDT`);

    // 2. Check actual USDT token balance at Insurance Fund
    const usdtBalance = await usdt.balanceOf(INSURANCE_FUND);
    console.log(`Insurance Fund USDT Token Balance: ${ethers.formatEther(usdtBalance)} USDT`);

    // 3. Check LeverVault TVL
    const tvl = await leverVault.totalAssets();
    console.log(`LeverVault TVL: ${ethers.formatEther(tvl)} USDT`);

    const shares = await leverVault.totalSupply();
    console.log(`LeverVault Shares: ${ethers.formatEther(shares)} lvUSDT`);
    console.log('');

    // 4. Check IFR
    console.log('=== INSURANCE FUND RATIO (IFR) ===');
    const ifr = await insuranceFund.getIFR();
    const target = await insuranceFund.getTarget();
    const floor = await insuranceFund.getFloor();
    const isFullyFunded = await insuranceFund.isFullyFunded();

    console.log(`Current IFR: ${ethers.formatEther(ifr)} (raw WAD value)`);
    console.log(`IFR Target (20% of TVL): ${ethers.formatEther(target)} USDT`);
    console.log(`IFR Floor (5% of TVL): ${ethers.formatEther(floor)} USDT`);
    console.log(`Is Fully Funded: ${isFullyFunded}`);

    // Calculate percentage
    if (tvl > 0) {
      const ifrPercent = Number(internalBalance * 10000n / tvl) / 100;
      console.log(`IFR Percentage: ${ifrPercent}%`);
    }
    console.log('');

    // 5. Check fee routing
    console.log('=== FEE ROUTING ===');
    const tier = await feeRouter.getCurrentTier();
    const [lpPct, protocolPct, insurancePct] = await feeRouter.getCurrentSplit();

    console.log(`Current Tier: ${tier}`);
    console.log(`Fee Split:`);
    console.log(`  LP: ${Number(lpPct * 100n / 10n**18n)}%`);
    console.log(`  Protocol: ${Number(protocolPct * 100n / 10n**18n)}%`);
    console.log(`  Insurance: ${Number(insurancePct * 100n / 10n**18n)}%`);
    console.log('');

    // 6. Check total fees routed
    console.log('=== TOTAL FEES ROUTED ===');
    try {
      // FeeType.TRANSACTION = 0, FeeType.BORROW = 1
      const txFees = await feeRouter.getTotalFeesRouted(0);
      const borrowFees = await feeRouter.getTotalFeesRouted(1);
      console.log(`Transaction Fees: ${ethers.formatEther(txFees)} USDT`);
      console.log(`Borrow Fees: ${ethers.formatEther(borrowFees)} USDT`);
      console.log(`Total Protocol Fees: ${ethers.formatEther(txFees + borrowFees)} USDT`);
    } catch (error) {
      console.log(`Error getting fee totals: ${error.message}`);
    }
    console.log('');

    // 7. Diagnosis
    console.log('=== DIAGNOSIS ===');
    if (tvl < 10n**18n) { // Less than 1 USDT
      console.log('ROOT CAUSE: TVL is essentially zero or very low');
      console.log(`  TVL: ${ethers.formatEther(tvl)} USDT`);
      console.log('');
      console.log('IMPACT:');
      console.log('  1. IFR = insurance_balance / TVL = very high percentage');
      console.log('  2. isFullyFunded() returns true (IFR > 20% target)');
      console.log('  3. FeeRouter switches to Tier 2 (50/50/0 split)');
      console.log('  4. Insurance fund receives 0% of new fees');
      console.log('');
      console.log('SOLUTION:');
      console.log('  Need LP deposits to increase TVL significantly');
      console.log('  Target: TVL > 50,000 USDT to bring IFR below 20%');
    } else if (isFullyFunded) {
      console.log('Insurance fund is legitimately fully funded (IFR >= 20%)');
      console.log('This is normal protocol behavior - fees go to protocol in Tier 2');
      console.log('This will switch back to Tier 1 when IFR drops below 20%');
    } else {
      console.log('Insurance fund should be receiving fees but is not fully funded');
      console.log('Check role permissions and fee generation');
    }

    // 8. Role checks
    console.log('');
    console.log('=== ROLE VERIFICATION ===');
    try {
      const FEE_ROUTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("FEE_ROUTER_ROLE"));
      const hasRole = await insuranceFund.hasRole(FEE_ROUTER_ROLE, FEE_ROUTER);
      console.log(`FeeRouter has FEE_ROUTER_ROLE on InsuranceFund: ${hasRole}`);
    } catch (error) {
      console.log(`Could not check roles: ${error.message}`);
    }

  } catch (error) {
    console.error('Error during investigation:', error);
  }
}

investigate().catch(console.error);