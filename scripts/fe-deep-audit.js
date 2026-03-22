const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const SCREENSHOT_DIR = '/home/lever/lever-protocol/screenshots/deep-audit';
const BASE_URL = 'http://165.245.186.254:3000';

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
let ssCount = 0;
async function ss(page, name) {
  ssCount++;
  const filePath = path.join(SCREENSHOT_DIR, `${String(ssCount).padStart(2,'0')}-${name}.png`);
  await page.screenshot({ path: filePath, fullPage: true });
  console.log(`  [SS] ${name}`);
}

async function main() {
  if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: '/usr/bin/chromium-browser',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--window-size=1920,1080']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });

  const jsErrors = [];
  page.on('pageerror', err => jsErrors.push(err.message));
  page.on('console', msg => {
    if (msg.type() === 'error' && !msg.text().includes('font') && !msg.text().includes('405')) {
      jsErrors.push(msg.text());
    }
  });

  // Expected correct values
  const EXPECTED = {
    tvl: '$10.00M',
    totalOI: '$0.00',
    utilization: '0.00%',
    insuranceFund: '$2,000,000', // actual on-chain is $2M USDT
    marketCount: 10,
    leverageMax: 5.4, // on-chain getEffectiveMaxLeverage
    vaultTVL: '$10,000,000',
    sharePrice: '$1.0000',
    newVaultAddr: '0x797E10F9F6BD7C725Fc8AD20A5e3330B1BF17360',
    newEEAddr: '0x31078bfe85d3f586edce8f5579d32448cb0586d6',
    newOIAddr: '0x905fe91236385733fb92f2f8af6300b0078e6f72',
    newLMAddr: '0x5c8a7016ab48484ea2704cd1abbe25fd23c27688',
  };

  const issues = [];
  function check(label, actual, expected, severity = 'ERROR') {
    if (actual === expected || (typeof expected === 'number' && Math.abs(actual - expected) < 0.5)) {
      console.log(`  ✓ ${label}: ${actual}`);
    } else {
      const msg = `${severity}: ${label}: got "${actual}", expected "${expected}"`;
      console.log(`  ✗ ${msg}`);
      issues.push(msg);
    }
  }

  try {
    // ===============================
    // TEST 1: DEPLOYMENT JSON INTEGRITY
    // ===============================
    console.log('\n========== TEST 1: DEPLOYMENT JSON INTEGRITY ==========');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(3000);

    const deployData = await page.evaluate(async () => {
      const [core, pool, engines] = await Promise.all([
        fetch('/deployments/core-deployment.json').then(r => r.json()),
        fetch('/deployments/pool-deployment.json').then(r => r.json()),
        fetch('/deployments/engines-deployment.json').then(r => r.json())
      ]);
      return { core, pool, engines };
    });

    check('leverVault JSON', deployData.pool.leverVault, EXPECTED.newVaultAddr);
    check('executionEngine JSON', deployData.engines.executionEngine, EXPECTED.newEEAddr);
    check('oiLimits JSON', deployData.engines.oiLimits, EXPECTED.newOIAddr);
    check('leverageModel JSON', deployData.engines.leverageModel, EXPECTED.newLMAddr);
    check('core.usdt unchanged', deployData.core.usdt, '0x5DaA593b6D7A6F3D3224471aC2D3905B54c2966E');
    check('core.positionManager unchanged', deployData.core.positionManager, '0x25ba54a7b2fBac753B601Da05e3661F2E959510b');

    await ss(page, 'deployment-json-check');

    // ===============================
    // TEST 2: STATS BAR ACCURACY
    // ===============================
    console.log('\n========== TEST 2: STATS BAR (top bar) ==========');
    await sleep(3000);

    const statsBar = await page.evaluate(() => {
      const text = document.body.innerText;
      const tvl = text.match(/TOTAL TVL[\s\S]*?\$([^\n]+)/)?.[1]?.trim();
      const volume = text.match(/TOTAL VOLUME[\s\S]*?\$?([^\n]+)/)?.[1]?.trim();
      const oi = text.match(/TOTAL OI[\s\S]*?\$([^\n]+)/)?.[1]?.trim();
      const apy = text.match(/LP APY[\s\S]*?([\d.]+%)/)?.[1]?.trim();
      const util = text.match(/UTILIZATION[\s\S]*?([\d.]+%)/)?.[1]?.trim();
      const insurance = text.match(/INSURANCE[\s\S]*?FUND[\s\S]*?\$([^\n]+)/)?.[1]?.trim();
      return { tvl, volume, oi, apy, util, insurance };
    });

    console.log('  Raw stats:', JSON.stringify(statsBar));
    check('TVL display', '$' + statsBar.tvl, EXPECTED.tvl);
    check('Insurance Fund display', '$' + statsBar.insurance, EXPECTED.insuranceFund, 'WARN');

    // ===============================
    // TEST 3: MARKETS PAGE - COUNT & DATA
    // ===============================
    console.log('\n========== TEST 3: MARKETS PAGE ==========');

    const marketsData = await page.evaluate(() => {
      // Count market cards
      const text = document.body.innerText;
      const activeMatch = text.match(/(\d+)\s*active\s*markets/i);
      // Count cards with "Long" and "Short" buttons
      const longBtns = document.querySelectorAll('button');
      let longCount = 0;
      longBtns.forEach(b => { if (b.textContent.trim() === 'Long') longCount++; });

      // Extract market names
      const marketNames = [];
      const marketTexts = ['SpaceX', 'US-Iran', 'Nothing', 'FIFA', 'Fed Rate', 'Ackman', 'AAPL', 'OpenSea', 'Fed April', 'Argentina'];
      marketTexts.forEach(name => {
        if (text.includes(name)) marketNames.push(name);
      });

      // Check for "LIVE" badges
      const liveBadges = text.match(/LIVE/g)?.length || 0;

      return { activeCount: activeMatch?.[1], longButtonCount: longCount, marketNames, liveBadges };
    });

    check('Active markets displayed', marketsData.longButtonCount, EXPECTED.marketCount);
    console.log(`  Markets found: ${marketsData.marketNames.join(', ')}`);
    console.log(`  LIVE badges: ${marketsData.liveBadges}`);
    await ss(page, 'markets-page');

    // ===============================
    // TEST 4: TRADING PAGE - LEVERAGE
    // ===============================
    console.log('\n========== TEST 4: TRADING PAGE ==========');

    // Click Trading tab
    await page.evaluate(() => {
      document.querySelectorAll('button, div, span').forEach(el => {
        if (el.textContent.trim() === 'Trading' && el.offsetHeight > 0) el.click();
      });
    });
    await sleep(5000);

    // Select first market
    await page.evaluate(() => {
      const select = document.querySelector('select');
      if (select) {
        select.value = select.options[1]?.value || '';
        select.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
    await sleep(3000);

    const tradingData = await page.evaluate(() => {
      const text = document.body.innerText;
      const maxLev = text.match(/max:\s*([\d.]+)x/i)?.[1];
      const depthBadge = text.match(/DEPTH\s*([\d.]+)?/)?.[0];
      const walletBal = text.match(/Wallet Balance:\s*([\d,.]+\s*\w+)/)?.[1];
      const availCollateral = text.match(/Available Collateral[\s\S]*?([\d,]+)\s*USDT/)?.[1];
      const usdtBalance = text.match(/USDT BALANCE[\s\S]*?([\d,.]+\s*\w+)/)?.[1];

      // Check leverage slider max
      const slider = document.querySelector('input[type="range"]');
      const sliderMax = slider?.max;

      return { maxLev, depthBadge, walletBal, availCollateral, usdtBalance, sliderMax };
    });

    console.log('  Raw trading data:', JSON.stringify(tradingData));
    check('Max leverage shown', parseFloat(tradingData.maxLev), EXPECTED.leverageMax, 'ERROR');
    check('Leverage slider max', parseFloat(tradingData.sliderMax), EXPECTED.leverageMax, 'ERROR');

    await ss(page, 'trading-page');

    // Select a market from dropdown
    const marketSelected = await page.evaluate(() => {
      const selects = document.querySelectorAll('select');
      for (const select of selects) {
        if (select.options.length > 1) {
          select.selectedIndex = 1;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          return select.options[1]?.text || 'selected';
        }
      }
      return 'no select found';
    });
    console.log(`  Market selected: ${marketSelected}`);
    await sleep(3000);

    // Re-check leverage after market selection
    const tradingData2 = await page.evaluate(() => {
      const text = document.body.innerText;
      const maxLev = text.match(/max:\s*([\d.]+)x/i)?.[1];
      const depthBadge = text.match(/([\d.]+)x\s*DEPTH/)?.[1];
      return { maxLev, depthBadge };
    });
    console.log(`  After market selection - max: ${tradingData2.maxLev}x, DEPTH: ${tradingData2.depthBadge}x`);
    await ss(page, 'trading-market-selected');

    // ===============================
    // TEST 5: VAULT PAGE - DATA ACCURACY
    // ===============================
    console.log('\n========== TEST 5: VAULT PAGE ==========');

    await page.evaluate(() => {
      document.querySelectorAll('button, div, span').forEach(el => {
        if (el.textContent.trim() === 'Vault' && el.offsetHeight > 0) el.click();
      });
    });
    await sleep(4000);

    const vaultData = await page.evaluate(() => {
      const text = document.body.innerText;
      const tvl = text.match(/TOTAL VALUE LOCKED[\s\S]*?\$([\d,]+)/)?.[1];
      const apy = text.match(/CURRENT APY[\s\S]*?([\d.]+%)/)?.[1];
      const util = text.match(/VAULT UTILIZATION[\s\S]*?([\d.]+%)/)?.[1];
      const sharePrice = text.match(/SHARE PRICE[\s\S]*?\$([\d.]+)/)?.[1];
      const yourShares = text.match(/YOUR SHARES[\s\S]*?([\d.]+)\s*lvUSDT/)?.[1];
      const yourValue = text.match(/VALUE[\s\S]*?\$([\d.]+)\s*USDT/)?.[1];
      const pendingYield = text.match(/PENDING YIELD[\s\S]*?\$([\d.]+)/)?.[1];
      const walletBal = text.match(/Wallet Balance:\s*([\d,.]+)/)?.[1];
      return { tvl, apy, util, sharePrice, yourShares, yourValue, pendingYield, walletBal };
    });

    console.log('  Raw vault data:', JSON.stringify(vaultData));
    check('Vault TVL', '$' + vaultData.tvl, EXPECTED.vaultTVL);
    check('Share price', '$' + vaultData.sharePrice, EXPECTED.sharePrice);

    await ss(page, 'vault-page');

    // ===============================
    // TEST 6: POSITIONS PAGE
    // ===============================
    console.log('\n========== TEST 6: POSITIONS PAGE ==========');

    await page.evaluate(() => {
      document.querySelectorAll('button, div, span').forEach(el => {
        if (el.textContent.trim() === 'Positions' && el.offsetHeight > 0) el.click();
      });
    });
    await sleep(4000);

    const posData = await page.evaluate(() => {
      const text = document.body.innerText;
      const noPositions = text.includes('No Open Positions');
      const hasPositionCards = text.includes('LONG') || text.includes('SHORT');
      const positionCount = (text.match(/LONG|SHORT/g) || []).length;
      return { noPositions, hasPositionCards, positionCount };
    });

    console.log(`  No positions message: ${posData.noPositions}`);
    console.log(`  Position cards found: ${posData.positionCount}`);
    if (posData.noPositions) {
      console.log('  ✓ Positions page correctly shows no open positions');
    }

    await ss(page, 'positions-page');

    // ===============================
    // TEST 7: MARKET DETAIL PAGE
    // ===============================
    console.log('\n========== TEST 7: MARKET DETAIL PAGE ==========');

    await page.evaluate(() => {
      document.querySelectorAll('button, div, span').forEach(el => {
        if (el.textContent.trim() === 'Market Detail' && el.offsetHeight > 0) el.click();
      });
    });
    await sleep(4000);

    const marketDetailData = await page.evaluate(() => {
      const text = document.body.innerText;
      const marketName = text.match(/(?:Largest IPO|SpaceX|US-Iran|Nothing|FIFA|Fed Rate|AAPL|OpenSea|Argentina)[^\n]*/)?.[0];
      const currentPrice = text.match(/Current Price[\s\S]*?([\d.]+)¢/)?.[1];
      const probability = text.match(/Probability[\s\S]*?([\d.]+%)/)?.[1];
      const totalOI = text.match(/Total OI[\s\S]*?\$([\d,.]+)/)?.[1];
      const resolution = text.match(/Resolution[\s\S]*?([\d]+d)/)?.[1];
      const fundingRate = text.match(/Funding Rate[\s\S]*?([\d.]+%)/)?.[1];
      const borrowRate = text.match(/Borrow Rate[\s\S]*?([\d.]+%)/)?.[1];
      const hasChart = text.includes('Price Chart');
      const hasOIBreakdown = text.includes('Open Interest Breakdown');

      // Check "Recent Positions" section
      const recentPositions = [];
      const posMatches = text.matchAll(/(LONG|SHORT)\s+\$([\d,.]+K?)\s+\n?(0x[a-fA-F0-9]+\.{2,3}[a-fA-F0-9]+)/g);
      for (const m of posMatches) {
        recentPositions.push({ dir: m[1], size: m[2], addr: m[3] });
      }

      return { marketName, currentPrice, probability, totalOI, resolution, fundingRate, borrowRate, hasChart, hasOIBreakdown, recentPositions };
    });

    console.log('  Raw market detail:', JSON.stringify(marketDetailData));
    console.log(`  Market: ${marketDetailData.marketName}`);
    console.log(`  Price chart: ${marketDetailData.hasChart}`);
    console.log(`  OI Breakdown: ${marketDetailData.hasOIBreakdown}`);
    console.log(`  Total OI: ${marketDetailData.totalOI}`);
    console.log(`  Recent positions count: ${marketDetailData.recentPositions.length}`);

    if (marketDetailData.recentPositions.length > 0) {
      issues.push('WARN: Market Detail shows "Recent Positions" data that may be stale/fake');
      marketDetailData.recentPositions.forEach(p => {
        console.log(`    ${p.dir} ${p.size} from ${p.addr}`);
      });
    }

    await ss(page, 'market-detail');

    // ===============================
    // TEST 8: FOOTER STATS
    // ===============================
    console.log('\n========== TEST 8: FOOTER STATS ==========');

    const footerData = await page.evaluate(() => {
      const text = document.body.innerText;
      const deployed = text.match(/DEPLOYED[\s\S]*?([\d-]+)/)?.[1];
      const version = text.match(/VERSION[\s\S]*?(v[\d.]+[^\n]*)/)?.[1];
      const marketsActive = text.match(/MARKETS[\s\S]*?(\d+)\s*ACTIVE/)?.[1];
      const users = text.match(/USERS[\s\S]*?(\d+)\s*DEMO/)?.[1];
      const sysOperational = text.includes('OPERATIONAL');
      const polymarket = text.includes('POLYMARKET');
      return { deployed, version, marketsActive, users, sysOperational, polymarket };
    });

    console.log('  Footer data:', JSON.stringify(footerData));
    check('Footer markets count', parseInt(footerData.marketsActive), EXPECTED.marketCount, 'WARN');

    await ss(page, 'footer');

    // ===============================
    // SUMMARY
    // ===============================
    console.log('\n========================================');
    console.log('           AUDIT SUMMARY');
    console.log('========================================');
    console.log(`\nTotal issues found: ${issues.length}`);
    issues.forEach((issue, i) => console.log(`  ${i+1}. ${issue}`));

    console.log(`\nJS Errors: ${jsErrors.length}`);
    jsErrors.slice(0, 5).forEach(e => console.log(`  - ${e.substring(0, 150)}`));

    console.log('\nScreenshots saved to:', SCREENSHOT_DIR);

  } catch (error) {
    console.error('Audit error:', error.message);
    await ss(page, 'error');
  } finally {
    await browser.close();
  }
}

main().catch(console.error);
