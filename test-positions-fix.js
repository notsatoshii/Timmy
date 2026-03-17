const puppeteer = require('puppeteer');

async function testPositionsTab() {
  console.log('Testing Positions tab fix...');

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding'
      ]
    });

    const page = await browser.newPage();

    // Set demo mode to avoid wallet connection
    await page.evaluateOnNewDocument(() => {
      localStorage.setItem('demo-mode', 'true');
    });

    // Navigate to frontend
    console.log('Navigating to frontend...');
    await page.goto('http://localhost:3000', {
      waitUntil: 'domcontentloaded',
      timeout: 15000
    });

    // Wait for React app to load
    console.log('Waiting for React app to load...');
    await page.waitForSelector('#root', { timeout: 10000 });

    // Check for any error boundaries or crashes
    const errorElements = await page.$$('text=Error');
    const errorBoundaryElements = await page.$$('text=Panel Error');

    console.log('Checking for React errors...');
    const reactErrors = await page.evaluate(() => {
      const errorMessages = [];
      const elements = document.querySelectorAll('*');
      for (let el of elements) {
        const text = el.textContent || '';
        if (text.includes('Error caught') ||
            text.includes('Panel Error') ||
            text.includes('BigInt') ||
            text.includes('Cannot read properties')) {
          errorMessages.push(text.slice(0, 100));
        }
      }
      return errorMessages;
    });

    // Try to access Positions tab if navigation exists
    console.log('Looking for navigation...');
    const navElements = await page.$$('nav');
    if (navElements.length > 0) {
      console.log('Found navigation, trying to click Positions...');
      const positionsLink = await page.$('text=Positions');
      if (positionsLink) {
        await positionsLink.click();
        await page.waitForTimeout(2000);

        // Check for errors after navigation
        const postNavErrors = await page.evaluate(() => {
          const errorMessages = [];
          const elements = document.querySelectorAll('*');
          for (let el of elements) {
            const text = el.textContent || '';
            if (text.includes('Error caught') ||
                text.includes('Panel Error') ||
                text.includes('BigInt')) {
              errorMessages.push(text.slice(0, 100));
            }
          }
          return errorMessages;
        });

        if (postNavErrors.length > 0) {
          console.log('❌ ERRORS FOUND after navigating to Positions:', postNavErrors);
          return false;
        }
      }
    }

    if (reactErrors.length > 0) {
      console.log('❌ ERRORS FOUND:', reactErrors);
      return false;
    }

    if (errorElements.length > 0 || errorBoundaryElements.length > 0) {
      console.log('❌ Error boundary elements found');
      return false;
    }

    console.log('✅ Positions tab fix SUCCESS - no errors detected');
    return true;

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return false;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

testPositionsTab().then(success => {
  process.exit(success ? 0 : 1);
});