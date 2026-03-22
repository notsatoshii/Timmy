const puppeteer = require('puppeteer');
const fs = require('fs');

const BASE_URL = 'http://localhost:3000';
const SCREENSHOT_DIR = '/home/lever/screenshots';
const PHASE = process.argv[2] || 'unknown';

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function screenshot(page, name) {
  const path = `${SCREENSHOT_DIR}/${PHASE}_${name}.png`;
  await page.screenshot({ path, fullPage: true });
  console.log(`Screenshot: ${path}`);
  return path;
}

async function run() {
  const browser = await puppeteer.launch({
    headless: 'new',
    executablePath: '/home/lever/local-libs/standalone-chrome/chrome',
    env: {
      ...process.env,
      LD_LIBRARY_PATH: '/home/lever/local-libs/standalone-chrome:/home/lever/local-libs/extracted-libs/usr/lib/x86_64-linux-gnu:' + (process.env.LD_LIBRARY_PATH || ''),
      CHROME_DEVEL_SANDBOX: '',
      DISPLAY: ''
    },
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--disable-software-rasterizer',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-web-security',
      '--disable-features=VizDisplayCompositor',
      '--disable-background-networking',
      '--ignore-certificate-errors',
      '--disable-extensions',
      '--mute-audio'
    ]
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });
  const errors = [];

  page.on('console', msg => {
    if (msg.type() === 'error') {
      const text = msg.text();
      // Ignore common non-critical errors
      if (!text.includes('405') && !text.includes('favicon') && !text.includes('prices.json')) {
        errors.push(text);
      }
    }
  });
  page.on('pageerror', err => errors.push(err.message));

  try {
    // MARKETS TAB
    console.log('\n=== Markets Tab ===');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 3000));
    await screenshot(page, '01_markets');

    const bodyText = await page.evaluate(() => document.body.innerText);
    if (bodyText.trim().length < 50) { errors.push('White screen detected'); }
    if (bodyText.includes('NaN') || bodyText.includes('undefined')) { errors.push('NaN/undefined on Markets'); }

    // Check no Roadmap tab
    const hasRoadmap = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('button, a, [role="tab"]')).some(t => t.textContent.trim() === 'Roadmap');
    });
    if (hasRoadmap) errors.push('Roadmap tab still exists');

    // Check no Market Detail tab
    const hasMarketDetailTab = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('button, a, [role="tab"]')).some(t => t.textContent.trim() === 'Market Detail');
    });
    if (hasMarketDetailTab) errors.push('Market Detail tab still exists');

    // TRADING TAB
    console.log('\n=== Trading Tab ===');
    await page.evaluate(() => {
      const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === 'Trading');
      if (tab) tab.click();
    });
    await new Promise(r => setTimeout(r, 2000));
    await screenshot(page, '02_trading');
    const tradingText = await page.evaluate(() => document.body.innerText);
    if (!tradingText.includes('Open Position') && !tradingText.includes('Collateral') && !tradingText.includes('Leverage')) {
      errors.push('Trading tab missing trade form');
    }

    // VAULT TAB
    console.log('\n=== Vault Tab ===');
    await page.evaluate(() => {
      const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === 'Vault');
      if (tab) tab.click();
    });
    await new Promise(r => setTimeout(r, 2000));
    await screenshot(page, '03_vault');
    const vaultText = await page.evaluate(() => document.body.innerText);
    if (vaultText.includes('$NaN') || vaultText.includes('NaN%')) errors.push('NaN on Vault tab');

    // POSITIONS TAB
    console.log('\n=== Positions Tab ===');
    await page.evaluate(() => {
      const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === 'Positions');
      if (tab) tab.click();
    });
    await new Promise(r => setTimeout(r, 2000));
    await screenshot(page, '04_positions');

    // CLICK FLOW: Market tile -> Detail -> Back
    console.log('\n=== Market Click Flow ===');
    await page.evaluate(() => {
      const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === 'Markets');
      if (tab) tab.click();
    });
    await new Promise(r => setTimeout(r, 5000)); // Wait longer for markets to load

    const clickedMarket = await page.evaluate(() => {
      // Try data-market-tile first (new tiles), then fallback selectors
      const tiles = document.querySelectorAll('[data-market-tile]');
      if (tiles.length > 0) { tiles[0].click(); return true; }
      // Fallback
      const cards = document.querySelectorAll('.cursor-pointer');
      for (const c of cards) {
        const text = c.innerText;
        if ((text.includes('%') || text.includes('¢')) && text.length > 20 && text.length < 800) {
          c.click(); return true;
        }
      }
      return false;
    });
    await new Promise(r => setTimeout(r, 4000));
    await screenshot(page, '05_market_detail');

    if (clickedMarket) {
      const detailLoaded = await page.evaluate(() => {
        const text = document.body.innerText;
        return text.includes('Price Chart') || text.includes('Current Price') || text.includes('Borrow Rate') || text.includes('Open Interest') || text.includes('Back to Markets') || text.includes('Open Position');
      });
      if (!detailLoaded) errors.push('Market detail did not load after clicking tile');

      const hasTradeForm = await page.evaluate(() => {
        return document.body.innerText.includes('Open Position') || document.body.innerText.includes('Position Details');
      });
      console.log(`Trade form in detail: ${hasTradeForm}`);

      // Click back
      await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll('button, a, span'));
        const back = links.find(l => l.textContent.includes('Back') || l.textContent.includes('←'));
        if (back) back.click();
      });
      await new Promise(r => setTimeout(r, 1500));
      await screenshot(page, '06_back_to_markets');
    }

    // STAT BAR CONTEXT CHECK
    console.log('\n=== Stat Bar Context ===');
    for (const tabName of ['Markets', 'Vault', 'Positions']) {
      await page.evaluate((name) => {
        const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === name);
        if (tab) tab.click();
      }, tabName);
      await new Promise(r => setTimeout(r, 1500));
      await screenshot(page, `07_statbar_${tabName.toLowerCase()}`);
    }

    // MATH CHECK
    console.log('\n=== Math Validation ===');
    await page.evaluate(() => {
      const tab = Array.from(document.querySelectorAll('button, a, [role="tab"]')).find(t => t.textContent.trim() === 'Markets');
      if (tab) tab.click();
    });
    await new Promise(r => setTimeout(r, 2000));
    const pageNums = await page.evaluate(() => {
      const text = document.body.innerText;
      const dollars = text.match(/\$[\d,]+\.?\d*/g) || [];
      const percents = text.match(/[\d.]+%/g) || [];
      return { dollars, percents };
    });
    for (const val of pageNums.dollars) {
      const num = parseFloat(val.replace(/[$,]/g, ''));
      if (num > 1e12) errors.push(`Suspicious value >$1T: ${val}`);
    }
    for (const val of pageNums.percents) {
      const num = parseFloat(val);
      if (num > 10000) errors.push(`Suspicious percent >10000%: ${val}`);
    }

  } catch (err) {
    errors.push(`Crash: ${err.message}`);
    await screenshot(page, 'ERROR');
  }

  await browser.close();

  console.log('\n========== REPORT ==========');
  console.log(`Phase: ${PHASE}`);
  console.log(`Errors: ${errors.length}`);
  errors.forEach((e, i) => console.log(`  ${i+1}. ${e}`));
  if (errors.length === 0) { console.log('\n✅ ALL TESTS PASSED'); }
  else { console.log('\n❌ TESTS FAILED — FIX BEFORE PROCEEDING'); process.exit(1); }
}
run();
