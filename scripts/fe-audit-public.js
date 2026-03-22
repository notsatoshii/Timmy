const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const SCREENSHOT_DIR = '/home/lever/lever-protocol/screenshots';
const BASE_URL = 'http://165.245.186.254:3000';

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function screenshot(page, name) {
  const filePath = path.join(SCREENSHOT_DIR, `${name}.png`);
  await page.screenshot({ path: filePath, fullPage: true });
  console.log(`  Screenshot: ${name}.png`);
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

  const errors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', err => errors.push(err.message));

  try {
    // 1. Markets page
    console.log('\n=== 1. MARKETS PAGE ===');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(5000);
    await screenshot(page, 'pub-01-markets');

    // Extract stats bar
    const stats = await page.evaluate(() => {
      const text = document.body.innerText;
      return text.substring(0, 600);
    });
    console.log('  Stats:', stats.substring(0, 300));

    // 2. Click "Trading" tab
    console.log('\n=== 2. TRADING TAB ===');
    const tradingClicked = await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button, a, div'));
      const trading = tabs.find(t => t.textContent.trim() === 'Trading');
      if (trading) { trading.click(); return true; }
      return false;
    });
    console.log('  Clicked Trading:', tradingClicked);
    await sleep(4000);
    await screenshot(page, 'pub-02-trading');

    // Extract leverage info
    const levInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      const maxMatch = text.match(/max:\s*([\d.]+)x/i);
      const depthMatch = text.match(/DEPTH\s*([\d.]+)x/i);
      return { max: maxMatch?.[1], depth: depthMatch?.[1] };
    });
    console.log('  Max leverage:', levInfo.max);
    console.log('  DEPTH:', levInfo.depth);

    // 3. Click "Vault" tab
    console.log('\n=== 3. VAULT TAB ===');
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button, a, div'));
      const vault = tabs.find(t => t.textContent.trim() === 'Vault');
      if (vault) vault.click();
    });
    await sleep(4000);
    await screenshot(page, 'pub-03-vault');

    const vaultInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      return text.substring(0, 800);
    });
    console.log('  Vault content:', vaultInfo.substring(0, 400));

    // 4. Click "Positions" tab
    console.log('\n=== 4. POSITIONS TAB ===');
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button, a, div'));
      const pos = tabs.find(t => t.textContent.trim() === 'Positions');
      if (pos) pos.click();
    });
    await sleep(4000);
    await screenshot(page, 'pub-04-positions');

    const posInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      return text.substring(0, 800);
    });
    console.log('  Positions content:', posInfo.substring(0, 400));

    // 5. Click "Market Detail" tab
    console.log('\n=== 5. MARKET DETAIL TAB ===');
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button, a, div'));
      const md = tabs.find(t => t.textContent.trim() === 'Market Detail');
      if (md) md.click();
    });
    await sleep(4000);
    await screenshot(page, 'pub-05-market-detail');

    // 6. Go back to Markets, click first market card
    console.log('\n=== 6. CLICK FIRST MARKET ===');
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button, a, div'));
      const mkt = tabs.find(t => t.textContent.trim() === 'Markets');
      if (mkt) mkt.click();
    });
    await sleep(3000);

    // Click first market card
    const clickedMarket = await page.evaluate(() => {
      // Look for market card elements
      const cards = document.querySelectorAll('[class*="market"], [class*="card"]');
      for (const card of cards) {
        if (card.textContent.includes('SpaceX') || card.textContent.includes('Largest IPO')) {
          card.click();
          return card.textContent.substring(0, 50);
        }
      }
      // Try clicking any element with market name
      const allEls = document.querySelectorAll('*');
      for (const el of allEls) {
        if (el.textContent.includes('SpaceX') && el.offsetHeight > 0 && el.offsetHeight < 200) {
          el.click();
          return 'clicked SpaceX element';
        }
      }
      return 'no market found to click';
    });
    console.log('  Clicked:', clickedMarket);
    await sleep(3000);
    await screenshot(page, 'pub-06-market-clicked');

    // 7. Errors summary
    console.log('\n=== JS ERRORS ===');
    if (errors.length > 0) {
      errors.slice(0, 10).forEach(e => console.log('  ERROR:', e.substring(0, 200)));
    } else {
      console.log('  No JS errors detected');
    }

  } catch (error) {
    console.error('Audit error:', error.message);
    await screenshot(page, 'pub-error');
  } finally {
    await browser.close();
  }
}

main().catch(console.error);
