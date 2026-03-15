const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const BASE = 'http://localhost:3000';
const SHOTS = '/home/lever/lever-protocol/frontend/screenshots/e2e';
fs.mkdirSync(SHOTS, { recursive: true });

let passed = 0, failed = 0;

async function test(page, name, fn) {
  try {
    await fn();
    console.log('PASS: ' + name);
    passed++;
  } catch (e) {
    console.log('FAIL: ' + name + ' — ' + e.message);
    await page.screenshot({ path: path.join(SHOTS, name.replace(/\s/g, '_') + '-FAIL.png'), fullPage: true });
    failed++;
  }
}

(async () => {
  const browser = await puppeteer.launch({
    headless: 'new',
    executablePath: '/usr/bin/chromium-browser',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  // 1. Page loads
  await test(page, 'Page loads', async () => {
    const res = await page.goto(BASE, { waitUntil: 'networkidle0', timeout: 30000 });
    if (res.status() !== 200) throw new Error('HTTP ' + res.status());
    await page.screenshot({ path: path.join(SHOTS, '01-homepage.png') });
  });

  // 2. No crash errors visible
  await test(page, 'No runtime errors overlay', async () => {
    const errorOverlay = await page.$('iframe[title="runtime error"]');
    if (errorOverlay) throw new Error('Runtime error overlay found');
  });

  // 3. Markets tab exists and has content
  await test(page, 'Markets tab visible', async () => {
    await page.waitForSelector('[data-testid="markets"], .markets, nav, button', { timeout: 5000 });
    const buttons = await page.$$('button, a, [role="tab"]');
    if (buttons.length < 2) throw new Error('No navigation found');
    await page.screenshot({ path: path.join(SHOTS, '02-markets.png') });
  });

  // 4. Check for market cards or list items
  await test(page, 'Market data renders', async () => {
    const text = await page.evaluate(() => document.body.innerText);
    const hasMarketContent = text.includes('Market') || text.includes('market') || text.includes('Long') || text.includes('Short');
    if (!hasMarketContent) throw new Error('No market content found on page');
  });

  // 5. Navigate to Trading
  await test(page, 'Trading panel accessible', async () => {
    const tabs = await page.$$('button, a, [role="tab"]');
    for (const tab of tabs) {
      const text = await page.evaluate(el => el.textContent, tab);
      if (text && text.toLowerCase().includes('trad')) {
        await tab.click();
        await new Promise(r => setTimeout(r, 2000));
        break;
      }
    }
    await page.screenshot({ path: path.join(SHOTS, '03-trading.png') });
    const text = await page.evaluate(() => document.body.innerText);
    const hasTradingContent = text.includes('Collateral') || text.includes('Leverage') || text.includes('Position') || text.includes('Long') || text.includes('Short');
    if (!hasTradingContent) throw new Error('Trading panel has no content');
  });

  // 6. Navigate to Vault
  await test(page, 'Vault panel accessible', async () => {
    const tabs = await page.$$('button, a, [role="tab"]');
    for (const tab of tabs) {
      const text = await page.evaluate(el => el.textContent, tab);
      if (text && text.toLowerCase().includes('vault') || text && text.toLowerCase().includes('earn')) {
        await tab.click();
        await new Promise(r => setTimeout(r, 2000));
        break;
      }
    }
    await page.screenshot({ path: path.join(SHOTS, '04-vault.png') });
    const text = await page.evaluate(() => document.body.innerText);
    const hasVaultContent = text.includes('TVL') || text.includes('APY') || text.includes('Deposit') || text.includes('Vault');
    if (!hasVaultContent) throw new Error('Vault panel has no content');
  });

  // 7. Navigate to Positions
  await test(page, 'Positions panel accessible', async () => {
    const tabs = await page.$$('button, a, [role="tab"]');
    for (const tab of tabs) {
      const text = await page.evaluate(el => el.textContent, tab);
      if (text && text.toLowerCase().includes('position') || text && text.toLowerCase().includes('portfolio')) {
        await tab.click();
        await new Promise(r => setTimeout(r, 2000));
        break;
      }
    }
    await page.screenshot({ path: path.join(SHOTS, '05-positions.png') });
  });

  // 8. Read-only mode works (no wallet connected)
  await test(page, 'Read-only mode — no wallet required', async () => {
    const text = await page.evaluate(() => document.body.innerText);
    const hasError = text.includes('Connect wallet to continue') && !text.includes('Market');
    if (hasError) throw new Error('App requires wallet to show any content');
  });

  // 9. Mobile viewport test
  await test(page, 'Mobile layout renders', async () => {
    await page.setViewport({ width: 375, height: 812 });
    await page.goto(BASE, { waitUntil: 'networkidle0', timeout: 30000 });
    await new Promise(r => setTimeout(r, 2000));
    await page.screenshot({ path: path.join(SHOTS, '06-mobile.png') });
    const text = await page.evaluate(() => document.body.innerText);
    if (text.length < 50) throw new Error('Mobile page has no content');
  });

  // 10. Check console errors
  await test(page, 'No critical console errors', async () => {
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.setViewport({ width: 1440, height: 900 });
    await page.goto(BASE, { waitUntil: 'networkidle0', timeout: 30000 });
    await new Promise(r => setTimeout(r, 3000));
    const critical = errors.filter(e => !e.includes('MetaMask') && !e.includes('Coinbase') && !e.includes('Porto'));
    if (critical.length > 0) throw new Error('Console errors: ' + critical.join(', '));
  });

  await browser.close();

  console.log('\n=== E2E TEST RESULTS ===');
  console.log('Passed: ' + passed);
  console.log('Failed: ' + failed);
  console.log('Screenshots: ' + SHOTS);

  if (failed > 0) {
    console.log('FAILED — check screenshots for details');
    process.exit(1);
  } else {
    console.log('ALL PASSED');
    process.exit(0);
  }
})();
