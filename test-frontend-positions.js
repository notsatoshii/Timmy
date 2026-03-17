const puppeteer = require('puppeteer');

(async () => {
  console.log('Starting browser test...');

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  // Listen to console logs
  page.on('console', msg => {
    const type = msg.type();
    const text = msg.text();

    // Only log our debugging messages to avoid noise
    if (text.includes('[Positions]') || text.includes('[createLivePosition]') ||
        text.includes('[total') || text.includes('formatWad') ||
        text.includes('Position values') || text.includes('$0.00')) {
      console.log(`[${type.toUpperCase()}] ${text}`);
    }
  });

  // Listen to errors
  page.on('pageerror', error => {
    console.error(`[PAGE ERROR] ${error.message}`);
  });

  try {
    console.log('Navigating to localhost:3000...');
    await page.goto('http://localhost:3000', {
      waitUntil: 'networkidle2',
      timeout: 30000
    });

    console.log('Waiting for positions to load...');
    // Wait for positions component to render
    await page.waitForTimeout(3000);

    // Navigate to positions tab
    console.log('Clicking positions tab...');
    const positionsTab = await page.$('button[data-testid="positions-tab"], button:contains("Positions"), a[href*="position"]');
    if (positionsTab) {
      await positionsTab.click();
      await page.waitForTimeout(2000);
    } else {
      // Try to find positions section or navigate directly
      console.log('Looking for positions section...');
      await page.evaluate(() => {
        // Look for any element that might contain positions
        const posElements = document.querySelectorAll('*');
        for (let elem of posElements) {
          if (elem.textContent && elem.textContent.toLowerCase().includes('position')) {
            elem.scrollIntoView();
            break;
          }
        }
      });
    }

    // Take a screenshot
    console.log('Taking screenshot...');
    await page.screenshot({ path: '/home/lever/lever-protocol/frontend-positions-debug.png', fullPage: true });

    // Get position values from the page
    console.log('Extracting position data from DOM...');
    const positionData = await page.evaluate(() => {
      const results = [];

      // Look for position cards or rows
      const positionElements = document.querySelectorAll('[data-testid*="position"], .position, div:has(text():contains("Position"))');

      positionElements.forEach((element, index) => {
        const text = element.textContent || '';

        // Look for dollar amounts
        const dollarMatches = text.match(/\$[\d,]+\.?\d*/g) || [];

        results.push({
          index,
          dollarAmounts: dollarMatches,
          hasZeroDollar: text.includes('$0.00'),
          snippet: text.substring(0, 200)
        });
      });

      // Also check for any elements containing $0.00
      const zeroElements = document.querySelectorAll('*');
      let zeroCount = 0;
      for (let elem of zeroElements) {
        if (elem.textContent && elem.textContent.includes('$0.00')) {
          zeroCount++;
        }
      }

      return {
        positions: results,
        zeroValueCount: zeroCount,
        pageTitle: document.title,
        bodyText: document.body.textContent.substring(0, 500)
      };
    });

    console.log('Position data extracted:', JSON.stringify(positionData, null, 2));

    // Wait a bit more to capture any delayed logs
    await page.waitForTimeout(2000);

  } catch (error) {
    console.error(`[BROWSER ERROR] ${error.message}`);
  } finally {
    console.log('Closing browser...');
    await browser.close();
  }
})();