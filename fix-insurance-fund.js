const { ethers } = require('ethers');
require('dotenv').config();

// Contract addresses from deploy-env.sh
const INSURANCE_FUND = '0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8';
const FEE_ROUTER = '0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F';
const USDT_ADDRESS = '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E';
const LEVER_VAULT = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';

// RPC URL
const RPC_URL = 'https://sepolia.base.org';

// Load private key from environment - will be loaded later

// ABIs for the operations we need
const MOCK_USDT_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address owner) view returns (uint256)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function decimals() view returns (uint8)'
];

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
  'function getTotalFeesRouted(uint8 feeType) view returns (uint256)'
];

const LEVER_VAULT_ABI = [
  'function totalAssets() view returns (uint256)',
  'function totalSupply() view returns (uint256)',
  'function deposit(uint256 assets, address receiver) returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)'
];

async function fixInsuranceFund() {
  console.log('=== FIXING INSURANCE FUND FLOW ===');
  console.log('Date: 2026-03-18');
  console.log('');

  try {
    // Load private key
    let privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
      const fs = require('fs');
      const deployerKeyPath = '/home/lever/lever-protocol/.env.deployer';
      if (fs.existsSync(deployerKeyPath)) {
        privateKey = fs.readFileSync(deployerKeyPath, 'utf8').trim();
      }
    }

    if (!privateKey) {
      throw new Error('Private key not found');
    }

    // Setup provider and signer
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const signer = new ethers.Wallet(privateKey, provider);

    console.log('Using address:', signer.address);

    // Connect to contracts
    const usdt = new ethers.Contract(USDT_ADDRESS, MOCK_USDT_ABI, signer);
    const insuranceFund = new ethers.Contract(INSURANCE_FUND, INSURANCE_FUND_ABI, provider);
    const feeRouter = new ethers.Contract(FEE_ROUTER, FEE_ROUTER_ABI, provider);
    const leverVault = new ethers.Contract(LEVER_VAULT, LEVER_VAULT_ABI, signer);

    // === BEFORE FIX ===
    console.log('=== BEFORE FIX ===');
    const internalBalance = await insuranceFund.getBalance();
    const actualUSDTBalance = await usdt.balanceOf(INSURANCE_FUND);
    const currentTVL = await leverVault.totalAssets();
    const currentIFR = await insuranceFund.getIFR();
    const currentTier = await feeRouter.getCurrentTier();
    const isFullyFunded = await insuranceFund.isFullyFunded();
    const deployerBalance = await usdt.balanceOf(signer.address);

    console.log(`Insurance Internal Balance: ${ethers.utils.formatEther(internalBalance)} USDT`);
    console.log(`Insurance USDT Balance: ${ethers.utils.formatEther(actualUSDTBalance)} USDT`);
    console.log(`Current TVL: ${ethers.utils.formatEther(currentTVL)} USDT`);
    console.log(`Current IFR: ${ethers.utils.formatEther(currentIFR)} (WAD)`);
    console.log(`Current Tier: ${currentTier}`);
    console.log(`Is Fully Funded: ${isFullyFunded}`);
    console.log(`Deployer USDT Balance: ${ethers.utils.formatEther(deployerBalance)} USDT`);
    console.log('');

    // Step 1: Calculate and mint USDT to align balances
    console.log('=== STEP 1: ALIGN USDT BALANCES ===');
    const usdtDeficit = internalBalance.sub(actualUSDTBalance);
    console.log(`USDT deficit to cover: ${ethers.utils.formatEther(usdtDeficit)} USDT`);

    if (usdtDeficit.gt(0)) {
      console.log('Minting USDT to cover deficit...');
      const mintTx = await usdt.mint(signer.address, usdtDeficit);
      await mintTx.wait();
      console.log(`Minted ${ethers.utils.formatEther(usdtDeficit)} USDT to deployer`);

      console.log('Transferring USDT to InsuranceFund...');
      const transferTx = await usdt.transfer(INSURANCE_FUND, usdtDeficit);
      await transferTx.wait();
      console.log(`Transferred ${ethers.utils.formatEther(usdtDeficit)} USDT to InsuranceFund`);

      // Verify alignment
      const newActualBalance = await usdt.balanceOf(INSURANCE_FUND);
      console.log(`New Insurance USDT Balance: ${ethers.utils.formatEther(newActualBalance)} USDT`);
    }

    // Step 2: Calculate required TVL for proper IFR
    console.log('');
    console.log('=== STEP 2: ADJUST TVL FOR PROPER IFR ===');
    const targetIFRPercent = 15; // Target 15% IFR (below 20% threshold)
    const targetTVL = internalBalance.mul(100).div(targetIFRPercent);
    const newTVL = await leverVault.totalAssets();
    const requiredVaultDeposit = targetTVL.gt(newTVL) ? targetTVL.sub(newTVL) : ethers.constants.Zero;

    console.log(`Target TVL for 15% IFR: ${ethers.utils.formatEther(targetTVL)} USDT`);
    console.log(`Required additional vault deposit: ${ethers.utils.formatEther(requiredVaultDeposit)} USDT`);

    if (requiredVaultDeposit.gt(0)) {
      console.log('Minting additional USDT for vault deposit...');
      const mintVaultTx = await usdt.mint(signer.address, requiredVaultDeposit);
      await mintVaultTx.wait();
      console.log(`Minted ${ethers.utils.formatEther(requiredVaultDeposit)} USDT`);

      console.log('Approving USDT for vault...');
      const approveTx = await usdt.approve(LEVER_VAULT, requiredVaultDeposit);
      await approveTx.wait();
      console.log('USDT approved for vault');

      console.log('Depositing to vault...');
      const depositTx = await leverVault.deposit(requiredVaultDeposit, signer.address);
      await depositTx.wait();
      console.log(`Deposited ${ethers.utils.formatEther(requiredVaultDeposit)} USDT to vault`);
    }

    // === AFTER FIX ===
    console.log('');
    console.log('=== AFTER FIX ===');
    const finalTVL = await leverVault.totalAssets();
    const finalInternalBalance = await insuranceFund.getBalance();
    const finalUSDTBalance = await usdt.balanceOf(INSURANCE_FUND);
    const finalIFR = await insuranceFund.getIFR();
    const finalTier = await feeRouter.getCurrentTier();
    const finallyFullyFunded = await insuranceFund.isFullyFunded();

    console.log(`Final TVL: ${ethers.utils.formatEther(finalTVL)} USDT`);
    console.log(`Insurance Internal Balance: ${ethers.utils.formatEther(finalInternalBalance)} USDT`);
    console.log(`Insurance USDT Balance: ${ethers.utils.formatEther(finalUSDTBalance)} USDT`);
    console.log(`Final IFR: ${ethers.utils.formatEther(finalIFR)} (WAD)`);
    console.log(`Final Tier: ${finalTier}`);
    console.log(`Is Fully Funded: ${finallyFullyFunded}`);

    // Calculate and display IFR percentage
    if (finalTVL.gt(0)) {
      const ifrPercent = finalInternalBalance.mul(10000).div(finalTVL);
      console.log(`Final IFR Percentage: ${ifrPercent.div(100).toString()}.${ifrPercent.mod(100).toString().padStart(2, '0')}%`);
    }

    // Get fee split
    const [lpPct, protocolPct, insurancePct] = await feeRouter.getCurrentSplit();
    console.log(`Fee Split - LP: ${lpPct.mul(100).div(ethers.utils.parseEther('1'))}% Protocol: ${protocolPct.mul(100).div(ethers.utils.parseEther('1'))}% Insurance: ${insurancePct.mul(100).div(ethers.utils.parseEther('1'))}%`);

    // Verify success
    console.log('');
    console.log('=== VERIFICATION ===');
    if (finalTier === 1 && !finallyFullyFunded && insurancePct.gt(0)) {
      console.log('🎉 [SUCCESS] Insurance fund flow restored!');
      console.log('- Tier switched to 1 (50/30/20 split)');
      console.log('- Insurance will now receive 20% of fees');
      console.log('- USDT balances are properly aligned');
    } else {
      console.log('⚠️ [PARTIAL SUCCESS] Some issues remain:');
      console.log(`- Final Tier: ${finalTier} (should be 1)`);
      console.log(`- Fully Funded: ${finallyFullyFunded} (should be false)`);
      console.log(`- Insurance Fee Share: ${insurancePct.mul(100).div(ethers.utils.parseEther('1'))}% (should be 20%)`);
    }

  } catch (error) {
    console.error('Error during fix:', error);
    throw error;
  }
}

// Private key will be loaded inside the function

fixInsuranceFund().catch(console.error);