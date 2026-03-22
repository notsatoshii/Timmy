const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const SCREENSHOT_DIR = '/home/lever/lever-protocol/screenshots';
const BASE_URL = 'http://localhost:3000';

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

  // Collect console logs for contract address debugging
  const consoleLogs = [];
  page.on('console', msg => {
    const text = msg.text();
    consoleLogs.push(text);
    if (text.includes('address') || text.includes('contract') || text.includes('deploy') || text.includes('leverage') || text.includes('vault')) {
      console.log(`  [Console] ${text}`);
    }
  });

  try {
    // 1. Landing / Markets page
    console.log('\n=== 1. MARKETS PAGE ===');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(3000);
    await screenshot(page, '01-markets-page');

    // 2. Check what deployment JSONs are loaded
    console.log('\n=== 2. CHECK DEPLOYMENT DATA ===');
    const deploymentData = await page.evaluate(async () => {
      try {
        const [core, pool, engines] = await Promise.all([
          fetch('/deployments/core-deployment.json').then(r => r.json()),
          fetch('/deployments/pool-deployment.json').then(r => r.json()),
          fetch('/deployments/engines-deployment.json').then(r => r.json())
        ]);
        return { core, pool, engines };
      } catch (e) {
        return { error: e.message };
      }
    });
    console.log('  Pool deployment (leverVault):', deploymentData.pool?.leverVault);
    console.log('  Engines deployment (leverageModel):', deploymentData.engines?.leverageModel);
    console.log('  Engines deployment (oiLimits):', deploymentData.engines?.oiLimits);
    console.log('  Engines deployment (executionEngine):', deploymentData.engines?.executionEngine);

    // 3. Trading page - first market
    console.log('\n=== 3. TRADING PAGE ===');
    await page.goto(`${BASE_URL}/trade`, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(4000);
    await screenshot(page, '02-trading-page');

    // Extract leverage info from page
    const leverageInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      const maxLevMatch = text.match(/max:\s*([\d.]+)x/i);
      const depthMatch = text.match(/DEPTH.*?([\d.]+)x/i);
      return {
        maxLeverage: maxLevMatch ? maxLevMatch[1] : 'not found',
        depthBadge: depthMatch ? depthMatch[1] : 'not found',
        bodySnippet: text.substring(0, 500)
      };
    });
    console.log('  Max leverage shown:', leverageInfo.maxLeverage);
    console.log('  DEPTH badge:', leverageInfo.depthBadge);

    // 4. Vault page
    console.log('\n=== 4. VAULT PAGE ===');
    await page.goto(`${BASE_URL}/vault`, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(4000);
    await screenshot(page, '03-vault-page');

    // Extract vault data
    const vaultInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      const tvlMatch = text.match(/TVL[:\s]*\$?([\d,.]+[KMB]?)/i);
      const apyMatch = text.match(/APY[:\s]*([\d.]+%?)/i);
      return {
        tvl: tvlMatch ? tvlMatch[1] : 'not found',
        apy: apyMatch ? apyMatch[1] : 'not found',
        bodySnippet: text.substring(0, 500)
      };
    });
    console.log('  TVL shown:', vaultInfo.tvl);
    console.log('  APY shown:', vaultInfo.apy);

    // 5. Positions page
    console.log('\n=== 5. POSITIONS PAGE ===');
    await page.goto(`${BASE_URL}/positions`, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(4000);
    await screenshot(page, '04-positions-page');

    const positionsInfo = await page.evaluate(() => {
      const text = document.body.innerText;
      return { bodySnippet: text.substring(0, 1000) };
    });
    console.log('  Positions content:', positionsInfo.bodySnippet.substring(0, 300));

    // 6. Click through each market detail
    console.log('\n=== 6. MARKET DETAIL PAGES ===');
    await page.goto(BASE_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(3000);

    // Find market cards/links
    const marketLinks = await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('a[href*="market"]'));
      return links.map(l => ({ href: l.href, text: l.innerText.substring(0, 50) }));
    });
    console.log(`  Found ${marketLinks.length} market links`);

    for (let i = 0; i < Math.min(marketLinks.length, 4); i++) {
      const link = marketLinks[i];
      console.log(`  Visiting: ${link.text.trim()}`);
      await page.goto(link.href, { waitUntil: 'networkidle2', timeout: 30000 });
      await sleep(3000);
      await screenshot(page, `05-market-detail-${i + 1}`);

      const marketDetailInfo = await page.evaluate(() => {
        const text = document.body.innerText;
        const oiMatch = text.match(/Open Interest[:\s]*([\d,.]+)/i);
        const leverageMatch = text.match(/Max Leverage[:\s]*([\d.]+)/i);
        return {
          oi: oiMatch ? oiMatch[1] : 'not found',
          leverage: leverageMatch ? leverageMatch[1] : 'not found'
        };
      });
      console.log(`    OI: ${marketDetailInfo.oi}, Max Leverage: ${marketDetailInfo.leverage}`);
    }

    // 7. Check if market detail pages exist via direct URL patterns
    if (marketLinks.length === 0) {
      console.log('  No market links found, trying direct URL patterns...');
      const marketSlugs = ['spacex-ipo', 'us-iran', 'nothing-happens', 'fifa'];
      for (const slug of marketSlugs) {
        try {
          await page.goto(`${BASE_URL}/market/${slug}`, { waitUntil: 'networkidle2', timeout: 10000 });
          await sleep(2000);
          await screenshot(page, `05-market-${slug}`);
        } catch (e) {
          console.log(`  ${slug}: failed to load`);
        }
      }
    }

    // 8. Summary
    console.log('\n=== AUDIT SUMMARY ===');
    console.log('Deployment JSON addresses (served at runtime):');
    console.log(`  leverVault: ${deploymentData.pool?.leverVault}`);
    console.log(`  leverageModel: ${deploymentData.engines?.leverageModel}`);
    console.log(`  oiLimits: ${deploymentData.engines?.oiLimits}`);
    console.log(`  executionEngine: ${deploymentData.engines?.executionEngine}`);
    console.log('');
    console.log('Expected NEW addresses:');
    console.log('  leverVault: 0x797E10F9F6BD7C725Fc8AD20A5e3330B1BF17360');
    console.log('  leverageModel: 0x5c8a7016ab48484ea2704cd1abbe25fd23c27688');
    console.log('  oiLimits: 0x905fe91236385733fb92f2f8af6300b0078e6f72');
    console.log('  executionEngine: 0x31078bfe85d3f586edce8f5579d32448cb0586d6');

    // Check match
    const vaultMatch = deploymentData.pool?.leverVault?.toLowerCase() === '0x797e10f9f6bd7c725fc8ad20a5e3330b1bf17360';
    const lmMatch = deploymentData.engines?.leverageModel?.toLowerCase() === '0x5c8a7016ab48484ea2704cd1abbe25fd23c27688';
    const oiMatch = deploymentData.engines?.oiLimits?.toLowerCase() === '0x905fe91236385733fb92f2f8af6300b0078e6f72';
    console.log(`\n  Vault address correct: ${vaultMatch}`);
    console.log(`  LeverageModel address correct: ${lmMatch}`);
    console.log(`  OILimits address correct: ${oiMatch}`);

    console.log('\nRelevant console logs:');
    consoleLogs.filter(l => l.includes('address') || l.includes('loaded') || l.includes('fallback')).forEach(l => console.log(`  ${l}`));

  } catch (error) {
    console.error('Audit error:', error.message);
    await screenshot(page, 'error-state');
  } finally {
    await browser.close();
  }
}

main().catch(console.error);
