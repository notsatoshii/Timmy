#!/usr/bin/env node
/**
 * React App Rendering Test
 * Uses puppeteer to actually load the page in a browser and check if React components render
 */

const puppeteer = require('puppeteer');

async function testReactRendering() {
  console.log('🚀 Testing React App Rendering with Browser...\n');

  let browser;
  try {
    // Launch browser in headless mode
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-web-security']
    });

    const page = await browser.newPage();

    // Set up console logging to capture JS errors
    const jsErrors = [];
    const logs = [];

    page.on('console', msg => {
      logs.push(`${msg.type()}: ${msg.text()}`);
      console.log(`Browser Console: ${msg.type()}: ${msg.text()}`);
    });

    page.on('pageerror', error => {
      jsErrors.push(error.message);
      console.log(`JavaScript Error: ${error.message}`);
    });

    console.log('1. Loading React app...');

    // Navigate to the frontend with timeout
    await page.goto('http://localhost:3000', {
      waitUntil: 'networkidle0',
      timeout: 30000
    });

    console.log('2. Waiting for React to mount...');

    // Wait for React to mount by checking for typical React elements
    try {
      await page.waitForSelector('[data-reactroot], .min-h-screen', { timeout: 10000 });
      console.log('   ✓ React app container found');
    } catch (error) {
      console.log('   ✗ React app container not found within 10s');
    }

    console.log('\n3. Checking for LEVER UI components...');

    // Test for specific LEVER components that should be visible
    const componentTests = [
      { name: 'Navigation/Header', selector: 'nav, header, [role="banner"]' },
      { name: 'Trading interface', selector: '[data-testid="trading"], .trading, .trade' },
      { name: 'Markets section', selector: '[data-testid="markets"], .markets' },
      { name: 'LP/Vault section', selector: '[data-testid="vault"], .vault' },
      { name: 'Main content area', selector: 'main, .dashboard, [role="main"]' },
      { name: 'Any React component', selector: '[data-reactroot] *, .min-h-screen *' }
    ];

    let foundComponents = 0;
    for (const test of componentTests) {
      try {
        const element = await page.$(test.selector);
        if (element) {
          console.log(`   ✓ ${test.name} found`);
          foundComponents++;
        } else {
          console.log(`   ✗ ${test.name} not found`);
        }
      } catch (error) {
        console.log(`   ✗ ${test.name} error: ${error.message}`);
      }
    }

    console.log('\n4. Checking page content...');

    // Get the full page content to see what's actually there
    const bodyText = await page.evaluate(() => document.body.textContent);
    const bodyHTML = await page.evaluate(() => document.body.innerHTML);

    console.log(`   Page text length: ${bodyText.length} characters`);
    console.log(`   Page HTML length: ${bodyHTML.length} characters`);

    // Check for typical loading indicators
    const hasLoadingText = bodyText.toLowerCase().includes('loading');
    const hasErrorText = bodyText.toLowerCase().includes('error');
    const hasLeverText = bodyText.toLowerCase().includes('lever');

    console.log(`   Contains "loading": ${hasLoadingText}`);
    console.log(`   Contains "error": ${hasErrorText}`);
    console.log(`   Contains "lever": ${hasLeverText}`);

    console.log('\n5. Taking screenshot...');

    // Take a screenshot to see what's actually rendered
    await page.screenshot({
      path: '/home/lever/lever-protocol/frontend/user-app/debug-screenshot.png',
      fullPage: true
    });
    console.log('   ✓ Screenshot saved to debug-screenshot.png');

    console.log('\n6. Checking for React errors...');

    if (jsErrors.length > 0) {
      console.log(`   ⚠️  Found ${jsErrors.length} JavaScript errors:`);
      jsErrors.forEach(error => console.log(`     - ${error}`));
    } else {
      console.log('   ✓ No JavaScript errors detected');
    }

    console.log('\n📊 Results Summary:');
    console.log(`   Components found: ${foundComponents}/${componentTests.length}`);
    console.log(`   JavaScript errors: ${jsErrors.length}`);
    console.log(`   Page has content: ${bodyText.length > 100}`);

    if (foundComponents === 0 && bodyText.length < 100) {
      console.log('\n❌ ISSUE DETECTED: React app appears to NOT be mounting properly');
      console.log('   The page loads but React components are not rendering');
      return false;
    } else if (foundComponents >= 2) {
      console.log('\n✅ React app appears to be working correctly');
      return true;
    } else {
      console.log('\n⚠️  React app partially working - some components missing');
      return false;
    }

  } catch (error) {
    console.error(`\n❌ Browser test failed: ${error.message}`);
    return false;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

testReactRendering().then(success => {
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('Test failed:', error);
  process.exit(1);
});