const puppeteer = require('puppeteer');

async function testVaultConsole() {
  console.log('=== VAULT CONSOLE TEST ===');

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  // Listen to console logs
  const logs = [];
  page.on('console', msg => {
    logs.push({
      type: msg.type(),
      text: msg.text(),
      timestamp: new Date().toISOString()
    });
  });

  // Listen to errors
  page.on('pageerror', error => {
    logs.push({
      type: 'pageerror',
      text: error.toString(),
      timestamp: new Date().toISOString()
    });
  });

  try {
    console.log('Loading http://localhost:3000...');
    await page.goto('http://localhost:3000', { waitUntil: 'networkidle0', timeout: 30000 });

    console.log('Waiting for React to load...');
    await page.waitForTimeout(5000);

    console.log('Clicking vault tab...');
    // Try to click the vault tab
    const vaultButton = await page.$('button[class*="tab"], button:has-text("Vault"), [role="tab"]:has-text("Vault")');
    if (vaultButton) {
      await vaultButton.click();
      await page.waitForTimeout(3000);
    } else {
      // Try alternative selectors
      const buttons = await page.$$('button');
      for (let button of buttons) {
        const text = await page.evaluate(el => el.textContent, button);
        if (text && text.toLowerCase().includes('vault')) {
          console.log('Found vault button:', text);
          await button.click();
          await page.waitForTimeout(3000);
          break;
        }
      }
    }

    console.log('Checking for vault data...');

    // Get page content to look for vault data
    const content = await page.content();
    const bodyText = await page.evaluate(() => document.body.innerText);

    // Check for NaN or undefined values
    const hasNaN = bodyText.includes('NaN') || bodyText.includes('undefined') || bodyText.includes('$NaN');
    const hasZeroTVL = bodyText.includes('$0') && bodyText.includes('Total Value');

    console.log('\n=== PAGE CONTENT ANALYSIS ===');
    console.log('Has NaN values:', hasNaN);
    console.log('Has $0 TVL:', hasZeroTVL);

    if (hasNaN) {
      // Find lines with NaN
      const lines = bodyText.split('\n').filter(line =>
        line.includes('NaN') || line.includes('undefined')
      );
      console.log('Lines with NaN:', lines);
    }

    // Look for specific vault elements
    const vaultStats = await page.$$eval('*', els =>
      els.filter(el =>
        el.textContent && (
          el.textContent.includes('Total Value Locked') ||
          el.textContent.includes('Share Price') ||
          el.textContent.includes('Current APY')
        )
      ).map(el => el.textContent.trim())
    );

    console.log('Vault stats found:', vaultStats);

    console.log('\n=== CONSOLE LOGS ===');

    // Filter and display relevant console logs
    const vaultLogs = logs.filter(log =>
      log.text.includes('VAULT') ||
      log.text.includes('multicall') ||
      log.text.includes('circuit') ||
      log.text.includes('fallback') ||
      log.type === 'error'
    );

    vaultLogs.forEach(log => {
      console.log(`[${log.type.toUpperCase()}] ${log.text}`);
    });

    if (vaultLogs.length === 0) {
      console.log('No vault-related logs found. Showing all logs:');
      logs.slice(-10).forEach(log => {
        console.log(`[${log.type.toUpperCase()}] ${log.text}`);
      });
    }

  } catch (error) {
    console.error('Test failed:', error);
  } finally {
    await browser.close();
  }

  console.log('\n=== TEST COMPLETE ===');
}

testVaultConsole().catch(console.error);