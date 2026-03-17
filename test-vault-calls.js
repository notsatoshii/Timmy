#!/usr/bin/env node

// Simple vault RPC test using cast commands
const { execSync } = require('child_process');

const contracts = {
  leverVault: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921",
  oiLimits: "0x5B9820B789785f62349bAE7e2B8A17a8e4A3E7cd",
  usdt: "0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E"
};

const RPC_URL = "https://sepolia.base.org";
const WAD = "1000000000000000000"; // 1e18

function runCast(command) {
  try {
    const result = execSync(command, { encoding: 'utf-8' }).trim();
    return result;
  } catch (error) {
    return `ERROR: ${error.message}`;
  }
}

function formatNumber(value, decimals) {
  try {
    const num = BigInt(value);
    const divisor = BigInt(10 ** decimals);
    const intPart = num / divisor;
    const fracPart = num % divisor;
    return `${intPart.toString()}.${fracPart.toString().padStart(decimals, '0')}`;
  } catch (error) {
    return 'PARSE_ERROR';
  }
}

console.log('=== VAULT CONTRACT TEST ===');
console.log(`Using RPC: ${RPC_URL}`);
console.log(`LeverVault: ${contracts.leverVault}`);
console.log(`OILimits: ${contracts.oiLimits}`);
console.log('');

console.log('1. Testing totalAssets...');
const totalAssetsCmd = `cast call ${contracts.leverVault} "totalAssets()(uint256)" --rpc-url ${RPC_URL}`;
const totalAssets = runCast(totalAssetsCmd);
console.log(`Raw result: ${totalAssets}`);
if (!totalAssets.includes('ERROR')) {
  console.log(`Formatted: ${formatNumber(totalAssets, 6)} USDT`);
}
console.log('');

console.log('2. Testing totalSupply...');
const totalSupplyCmd = `cast call ${contracts.leverVault} "totalSupply()(uint256)" --rpc-url ${RPC_URL}`;
const totalSupply = runCast(totalSupplyCmd);
console.log(`Raw result: ${totalSupply}`);
if (!totalSupply.includes('ERROR')) {
  console.log(`Formatted: ${formatNumber(totalSupply, 18)} shares`);
}
console.log('');

console.log('3. Testing convertToAssets (share price)...');
const sharePriceCmd = `cast call ${contracts.leverVault} "convertToAssets(uint256)(uint256)" ${WAD} --rpc-url ${RPC_URL}`;
const sharePrice = runCast(sharePriceCmd);
console.log(`Raw result: ${sharePrice}`);
if (!sharePrice.includes('ERROR')) {
  console.log(`Formatted: ${formatNumber(sharePrice, 12)} USDT per share (converted from 6 to 18 decimals)`);
}
console.log('');

console.log('4. Testing getGlobalOI...');
const globalOICmd = `cast call ${contracts.oiLimits} "getGlobalOI()(uint256)" --rpc-url ${RPC_URL}`;
const globalOI = runCast(globalOICmd);
console.log(`Raw result: ${globalOI}`);
if (!globalOI.includes('ERROR')) {
  console.log(`Formatted: ${formatNumber(globalOI, 6)} USDT`);
}
console.log('');

// Calculate values
console.log('5. Calculations...');
try {
  if (!totalAssets.includes('ERROR') && !totalSupply.includes('ERROR') && !sharePrice.includes('ERROR') && !globalOI.includes('ERROR')) {
    const assets = BigInt(totalAssets);
    const supply = BigInt(totalSupply);
    const oi = BigInt(globalOI);

    const tvlUSD = Number(assets) / 1e6;
    const sharesFloat = Number(supply) / 1e18;
    const calculatedSharePrice = sharesFloat > 0 ? tvlUSD / sharesFloat : 1.0;
    const utilization = tvlUSD > 0 ? (Number(oi) / 1e6) / tvlUSD * 100 : 0;

    console.log(`TVL: $${tvlUSD.toLocaleString()}`);
    console.log(`Total Shares: ${sharesFloat.toLocaleString()}`);
    console.log(`Calculated Share Price: $${calculatedSharePrice.toFixed(4)}`);
    console.log(`Contract Share Price: $${(Number(sharePrice) / 1e12).toFixed(4)}`);
    console.log(`Utilization: ${utilization.toFixed(1)}%`);

    // Check for problems
    if (isNaN(calculatedSharePrice) || !isFinite(calculatedSharePrice)) {
      console.log('❌ ISSUE: Calculated share price is NaN or infinite');
    }

    if (tvlUSD === 0) {
      console.log('❌ ISSUE: TVL is zero');
    }

    if (sharesFloat === 0) {
      console.log('❌ ISSUE: Total shares is zero');
    }

    if (calculatedSharePrice !== (Number(sharePrice) / 1e12)) {
      console.log('⚠️ WARNING: Calculated and contract share prices differ');
    }

  } else {
    console.log('❌ Cannot calculate - some contract calls failed');
  }
} catch (error) {
  console.log(`❌ Calculation error: ${error.message}`);
}

console.log('\n=== TEST COMPLETE ===');