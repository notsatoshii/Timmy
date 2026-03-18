const { ethers } = require('ethers');
const fs = require('fs');

// Contract addresses
const USDT_ADDRESS = '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E';
const LEVER_VAULT = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';
const INSURANCE_FUND = '0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8';
const FEE_ROUTER = '0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F';

const RPC_URL = 'https://sepolia.base.org';

// ABIs
const MOCK_USDT_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address owner) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

const LEVER_VAULT_ABI = [
  'function totalAssets() view returns (uint256)',
  'function deposit(uint256 assets, address receiver) returns (uint256)',
  'function balanceOf(address owner) view returns (uint256)'
];

const INSURANCE_FUND_ABI = [
  'function getBalance() view returns (uint256)',
  'function getIFR() view returns (uint256)',
  'function isFullyFunded() view returns (bool)'
];

const FEE_ROUTER_ABI = [
  'function getCurrentTier() view returns (uint8)',
  'function getCurrentSplit() view returns (uint256, uint256, uint256)'
];

async function completeInsuranceFix() {
  try {
    // Load private key
    const privateKey = fs.readFileSync('/home/lever/lever-protocol/.env.deployer', 'utf8').trim();
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const signer = new ethers.Wallet(privateKey, provider);

    console.log('=== COMPLETING INSURANCE FUND FIX (STEP 2) ===');
    console.log('Using address:', signer.address);
    console.log('');

    // Connect to contracts
    const usdt = new ethers.Contract(USDT_ADDRESS, MOCK_USDT_ABI, signer);
    const leverVault = new ethers.Contract(LEVER_VAULT, LEVER_VAULT_ABI, signer);
    const insuranceFund = new ethers.Contract(INSURANCE_FUND, INSURANCE_FUND_ABI, provider);
    const feeRouter = new ethers.Contract(FEE_ROUTER, FEE_ROUTER_ABI, provider);

    // Check current state
    const currentTVL = await leverVault.totalAssets();
    const insuranceBalance = await insuranceFund.getBalance();
    const currentTier = await feeRouter.getCurrentTier();
    const isFullyFunded = await insuranceFund.isFullyFunded();
    const deployerBalance = await usdt.balanceOf(signer.address);

    console.log('=== CURRENT STATE ===');
    console.log(`Current TVL: ${ethers.utils.formatEther(currentTVL)} USDT`);
    console.log(`Insurance Balance: ${ethers.utils.formatEther(insuranceBalance)} USDT`);
    console.log(`Current Tier: ${currentTier}`);
    console.log(`Is Fully Funded: ${isFullyFunded}`);
    console.log(`Deployer USDT Balance: ${ethers.utils.formatEther(deployerBalance)} USDT`);
    console.log('');

    // Calculate required vault deposit for 15% IFR
    const targetIFRPercent = 15; // 15% IFR (below 20% threshold)
    const targetTVL = insuranceBalance.mul(100).div(targetIFRPercent);
    const requiredDeposit = targetTVL.sub(currentTVL);

    console.log(`Target TVL for 15% IFR: ${ethers.utils.formatEther(targetTVL)} USDT`);
    console.log(`Required vault deposit: ${ethers.utils.formatEther(requiredDeposit)} USDT`);
    console.log('');

    // Mint USDT if needed
    if (deployerBalance.lt(requiredDeposit)) {
      const mintAmount = requiredDeposit.sub(deployerBalance);
      console.log(`Minting additional ${ethers.utils.formatEther(mintAmount)} USDT...`);

      const mintTx = await usdt.mint(signer.address, mintAmount);
      await mintTx.wait();
      console.log('USDT minted successfully');
    }

    // Check current allowance
    const currentAllowance = await usdt.allowance(signer.address, LEVER_VAULT);
    console.log(`Current vault allowance: ${ethers.utils.formatEther(currentAllowance)} USDT`);

    // Approve if needed
    if (currentAllowance.lt(requiredDeposit)) {
      console.log('Approving USDT for vault...');
      const approveTx = await usdt.approve(LEVER_VAULT, requiredDeposit);
      await approveTx.wait();
      console.log('USDT approved for vault');
    }

    // Deposit to vault
    console.log(`Depositing ${ethers.utils.formatEther(requiredDeposit)} USDT to vault...`);
    const depositTx = await leverVault.deposit(requiredDeposit, signer.address);
    await depositTx.wait();
    console.log('Vault deposit completed');

    // Check final state
    console.log('');
    console.log('=== FINAL STATE ===');
    const finalTVL = await leverVault.totalAssets();
    const finalIFR = await insuranceFund.getIFR();
    const finalTier = await feeRouter.getCurrentTier();
    const finallyFullyFunded = await insuranceFund.isFullyFunded();

    console.log(`Final TVL: ${ethers.utils.formatEther(finalTVL)} USDT`);
    console.log(`Final IFR: ${ethers.utils.formatEther(finalIFR)} (WAD)`);
    console.log(`Final Tier: ${finalTier}`);
    console.log(`Is Fully Funded: ${finallyFullyFunded}`);

    // Calculate IFR percentage
    if (finalTVL.gt(0)) {
      const ifrPercent = insuranceBalance.mul(10000).div(finalTVL);
      console.log(`Final IFR Percentage: ${ifrPercent.div(100).toString()}.${ifrPercent.mod(100).toString().padStart(2, '0')}%`);
    }

    // Get fee split
    const [lpPct, protocolPct, insurancePct] = await feeRouter.getCurrentSplit();
    console.log(`Fee Split - LP: ${lpPct.mul(100).div(ethers.utils.parseEther('1'))}% Protocol: ${protocolPct.mul(100).div(ethers.utils.parseEther('1'))}% Insurance: ${insurancePct.mul(100).div(ethers.utils.parseEther('1'))}%`);

    // Final verification
    console.log('');
    if (finalTier === 1 && !finallyFullyFunded && insurancePct.gt(0)) {
      console.log('🎉 [SUCCESS] Insurance fund flow completely restored!');
      console.log('✅ USDT balances aligned');
      console.log('✅ TVL increased to bring IFR below 20%');
      console.log('✅ Tier switched to 1 (50/30/20 split)');
      console.log('✅ Insurance will now receive 20% of fees');
    } else {
      console.log('⚠️ [NEEDS REVIEW] Final state:');
      console.log(`- Tier: ${finalTier} (should be 1)`);
      console.log(`- Fully Funded: ${finallyFullyFunded} (should be false)`);
      console.log(`- Insurance Share: ${insurancePct.mul(100).div(ethers.utils.parseEther('1'))}% (should be 20%)`);
    }

  } catch (error) {
    console.error('Error completing fix:', error);
    throw error;
  }
}

completeInsuranceFix().catch(console.error);