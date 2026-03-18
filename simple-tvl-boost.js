const { ethers } = require('ethers');
const fs = require('fs');

// Contract addresses
const USDT_ADDRESS = '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E';
const LEVER_VAULT = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';
const INSURANCE_FUND = '0x39aca7f8cbb4b054c2f6aad637a61942898b1ae8';
const FEE_ROUTER = '0x1d6e55260C6Dd2A20A5bb7Cb6331E6Ba2faB5b6F';

const RPC_URL = 'https://sepolia.base.org';

const MOCK_USDT_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address owner) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)'
];

const LEVER_VAULT_ABI = [
  'function totalAssets() view returns (uint256)',
  'function deposit(uint256 assets, address receiver) returns (uint256)'
];

const INSURANCE_FUND_ABI = [
  'function getBalance() view returns (uint256)',
  'function isFullyFunded() view returns (bool)'
];

const FEE_ROUTER_ABI = [
  'function getCurrentTier() view returns (uint8)',
  'function getCurrentSplit() view returns (uint256, uint256, uint256)'
];

async function simpleTVLBoost() {
  try {
    console.log('=== SIMPLE TVL BOOST FOR INSURANCE FUND FIX ===');

    const privateKey = fs.readFileSync('/home/lever/lever-protocol/.env.deployer', 'utf8').trim();
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const signer = new ethers.Wallet(privateKey, provider);

    const usdt = new ethers.Contract(USDT_ADDRESS, MOCK_USDT_ABI, signer);
    const leverVault = new ethers.Contract(LEVER_VAULT, LEVER_VAULT_ABI, signer);
    const insuranceFund = new ethers.Contract(INSURANCE_FUND, INSURANCE_FUND_ABI, provider);
    const feeRouter = new ethers.Contract(FEE_ROUTER, FEE_ROUTER_ABI, provider);

    console.log('Using address:', signer.address);
    console.log('');

    // Get current state
    const insuranceBalance = await insuranceFund.getBalance();
    const currentTVL = await leverVault.totalAssets();
    const currentTier = await feeRouter.getCurrentTier();

    console.log('=== CURRENT STATE ===');
    console.log(`Insurance Balance: ${ethers.utils.formatEther(insuranceBalance)} USDT`);
    console.log(`Current TVL: ${ethers.utils.formatEther(currentTVL)} USDT`);
    console.log(`Current Tier: ${currentTier}`);
    console.log('');

    // Try smaller deposit amounts to avoid oracle issues
    // Target: Just get IFR below 20% (currently it's way too high)
    const depositAmount = ethers.utils.parseEther('30000000'); // 30M USDT

    console.log(`Attempting to deposit: ${ethers.utils.formatEther(depositAmount)} USDT`);

    // Mint USDT
    console.log('Minting USDT...');
    const mintTx = await usdt.mint(signer.address, depositAmount);
    await mintTx.wait();
    console.log('USDT minted successfully');

    // Approve in smaller chunks to avoid oracle issues
    console.log('Approving USDT...');
    const approveTx = await usdt.approve(LEVER_VAULT, depositAmount);
    await approveTx.wait();
    console.log('Approval successful');

    // Deposit to vault
    console.log('Depositing to vault...');
    const depositTx = await leverVault.deposit(depositAmount, signer.address);
    await depositTx.wait();
    console.log('Deposit successful');

    // Check results
    const newTVL = await leverVault.totalAssets();
    const newTier = await feeRouter.getCurrentTier();
    const isFullyFunded = await insuranceFund.isFullyFunded();

    console.log('');
    console.log('=== RESULTS ===');
    console.log(`New TVL: ${ethers.utils.formatEther(newTVL)} USDT`);
    console.log(`New Tier: ${newTier}`);
    console.log(`Is Fully Funded: ${isFullyFunded}`);

    // Calculate IFR percentage
    if (newTVL.gt(0)) {
      const ifrPercent = insuranceBalance.mul(10000).div(newTVL);
      console.log(`New IFR: ${ifrPercent.div(100).toString()}.${ifrPercent.mod(100).toString()}%`);
    }

    // Check fee split
    const [lpPct, protocolPct, insurancePct] = await feeRouter.getCurrentSplit();
    console.log(`Fee Split - LP: ${lpPct.mul(100).div(ethers.utils.parseEther('1'))}% Protocol: ${protocolPct.mul(100).div(ethers.utils.parseEther('1'))}% Insurance: ${insurancePct.mul(100).div(ethers.utils.parseEther('1'))}%`);

    if (newTier === 1 && !isFullyFunded && insurancePct.gt(0)) {
      console.log('');
      console.log('🎉 SUCCESS! Insurance fund flow restored!');
      console.log('✅ Tier 1 active (50/30/20 split)');
      console.log('✅ Insurance fund will now receive 20% of fees');
    } else if (newTier === 2) {
      console.log('');
      console.log('⚠️ Still in Tier 2 - need more TVL to lower IFR below 20%');
    }

  } catch (error) {
    console.error('Error:', error);
  }
}

simpleTVLBoost().catch(console.error);