const puppeteer = require('puppeteer-core');
const fs = require('fs');

async function testMobileResponsive() {
  console.log('=== LEVER Mobile Responsiveness Test ===');
  console.log('Target width: 375px (iPhone SE / small mobile)');

  let browser = null;

  try {
    // Launch browser with mobile viewport
    browser = await puppeteer.launch({
      executablePath: '/snap/bin/chromium',
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--no-first-run',
        '--disable-extensions',
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding'
      ]
    });

    const page = await browser.newPage();

    // Set mobile viewport
    await page.setViewport({ width: 375, height: 667 });

    // Navigate to the app
    console.log('\n[1/6] Loading app on localhost:3000...');
    await page.goto('http://localhost:3000', {
      waitUntil: 'networkidle0',
      timeout: 30000
    });

    // Check for horizontal overflow
    console.log('[2/6] Checking for horizontal overflow...');
    const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    const viewportWidth = 375;

    if (documentWidth > viewportWidth) {
      console.log(`  ❌ OVERFLOW DETECTED: Document width ${documentWidth}px > viewport ${viewportWidth}px`);
    } else {
      console.log(`  ✅ No overflow: Document width ${documentWidth}px fits in ${viewportWidth}px`);
    }

    // Check tab navigation on mobile
    console.log('[3/6] Testing mobile navigation tabs...');
    const mobileNav = await page.$('.md\\:hidden .grid.grid-cols-4');
    if (mobileNav) {
      console.log('  ✅ Mobile navigation found (4-column grid)');
    } else {
      console.log('  ⚠️  Mobile navigation not found');
    }

    // Check responsive text sizes
    console.log('[4/6] Checking text readability...');
    const smallText = await page.$$eval('*', elements => {
      return elements.filter(el => {
        const computedStyle = window.getComputedStyle(el);
        const fontSize = parseInt(computedStyle.fontSize);
        return fontSize < 12 && el.textContent.trim().length > 0;
      }).length;
    });

    if (smallText > 0) {
      console.log(`  ⚠️  Found ${smallText} elements with text smaller than 12px`);
    } else {
      console.log('  ✅ All text appears readable (≥12px)');
    }

    // Test each main tab
    console.log('[5/6] Testing tab responsiveness...');
    const tabs = ['markets', 'trading', 'vault', 'positions'];

    for (const tab of tabs) {
      // Click tab (try mobile nav first, then desktop)
      const tabButton = await page.$(`button[class*="text-${tab === 'markets' ? 'primary' : 'gray'}"]`) ||
                       await page.$(`button:contains("${tab.charAt(0).toUpperCase() + tab.slice(1)}")`);

      if (tabButton) {
        await tabButton.click();
        await page.waitForTimeout(500); // Wait for tab to load

        // Check for overflow in this tab
        const tabWidth = await page.evaluate(() => document.documentElement.scrollWidth);

        if (tabWidth > viewportWidth) {
          console.log(`  ❌ ${tab.toUpperCase()} tab overflow: ${tabWidth}px > ${viewportWidth}px`);
        } else {
          console.log(`  ✅ ${tab.toUpperCase()} tab fits: ${tabWidth}px`);
        }
      }
    }

    // Check button tap targets
    console.log('[6/6] Checking button tap targets...');
    const smallButtons = await page.$$eval('button', buttons => {
      return buttons.filter(btn => {
        const rect = btn.getBoundingClientRect();
        return rect.width < 44 || rect.height < 44; // iOS minimum tap target
      }).length;
    });

    if (smallButtons > 0) {
      console.log(`  ⚠️  Found ${smallButtons} buttons smaller than 44px (iOS minimum tap target)`);
    } else {
      console.log('  ✅ All buttons meet minimum tap target size');
    }

    console.log('\n=== MOBILE TEST COMPLETE ===');
    return true;

  } catch (error) {
    console.error(`❌ Mobile test failed: ${error.message}`);
    return false;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

testMobileResponsive()
  .then(success => process.exit(success ? 0 : 1))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });