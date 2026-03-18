#!/usr/bin/env node

const puppeteer = require('puppeteer-core');
const fs = require('fs');

async function testFrontendMounting() {
    console.log('🧪 Testing Frontend React App Mounting...\n');

    let browser;
    try {
        // Try different browser paths
        const browserPaths = [
            '/usr/bin/google-chrome',
            '/usr/bin/chromium-browser',
            '/usr/bin/chromium',
            '/snap/bin/chromium'
        ];

        let browserPath = null;
        for (const path of browserPaths) {
            if (fs.existsSync(path)) {
                browserPath = path;
                break;
            }
        }

        if (!browserPath) {
            console.log('❌ No Chrome/Chromium browser found. Falling back to HTTP checks...\n');
            return await fallbackHttpChecks();
        }

        console.log(`📖 Using browser: ${browserPath}`);

        browser = await puppeteer.launch({
            executablePath: browserPath,
            headless: 'new',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-accelerated-2d-canvas',
                '--no-first-run',
                '--no-zygote',
                '--disable-gpu'
            ]
        });

        const page = await browser.newPage();

        // Capture console logs
        const consoleLogs = [];
        page.on('console', msg => {
            consoleLogs.push(`${msg.type()}: ${msg.text()}`);
        });

        // Capture errors
        const pageErrors = [];
        page.on('pageerror', error => {
            pageErrors.push(error.toString());
        });

        console.log('🌐 Loading main page...');
        await page.goto('http://localhost:3000', { waitUntil: 'networkidle0', timeout: 10000 });

        // Wait for React to potentially mount
        await page.waitForTimeout(3000);

        console.log('🔍 Checking page state...\n');

        // Check if root element exists
        const rootExists = await page.$('#root');
        console.log(`✓ Root element exists: ${rootExists ? 'YES' : 'NO'}`);

        if (rootExists) {
            // Check root content
            const rootContent = await page.$eval('#root', el => el.innerHTML);
            console.log(`✓ Root content length: ${rootContent.length} characters`);

            if (rootContent.length > 100) {
                console.log('✅ React app appears to be mounted and rendered');

                // Check for specific LEVER components
                const hasHeader = await page.$('header, [data-testid="header"], nav') !== null;
                const hasMarkets = rootContent.includes('Markets') || rootContent.includes('market');
                const hasTrading = rootContent.includes('Trading') || rootContent.includes('trade');
                const hasConnectWallet = rootContent.includes('Connect') || rootContent.includes('wallet');

                console.log(`  • Header/Navigation: ${hasHeader ? 'FOUND' : 'NOT FOUND'}`);
                console.log(`  • Markets content: ${hasMarkets ? 'FOUND' : 'NOT FOUND'}`);
                console.log(`  • Trading content: ${hasTrading ? 'FOUND' : 'NOT FOUND'}`);
                console.log(`  • Wallet connection: ${hasConnectWallet ? 'FOUND' : 'NOT FOUND'}`);

                if (!hasHeader && !hasMarkets && !hasTrading) {
                    console.log('⚠️  WARNING: React mounted but LEVER components not detected');
                }
            } else {
                console.log('❌ Root element is empty or has minimal content');
            }
        }

        // Check for JavaScript errors
        console.log('\n🐛 JavaScript Console Output:');
        if (consoleLogs.length === 0) {
            console.log('  (no console output)');
        } else {
            consoleLogs.slice(0, 10).forEach(log => console.log(`  ${log}`));
            if (consoleLogs.length > 10) {
                console.log(`  ... and ${consoleLogs.length - 10} more entries`);
            }
        }

        console.log('\n❌ Page Errors:');
        if (pageErrors.length === 0) {
            console.log('  (no page errors)');
        } else {
            pageErrors.forEach(error => console.log(`  ${error}`));
        }

        // Take a screenshot
        const screenshot = await page.screenshot({
            type: 'png',
            fullPage: true
        });

        const screenshotPath = '/home/lever/lever-protocol/control-plane/screenshots/frontend-test.png';
        fs.writeFileSync(screenshotPath, screenshot);
        console.log(`\n📸 Screenshot saved: ${screenshotPath}`);

        return {
            success: rootExists && rootContent.length > 100,
            details: {
                rootExists: !!rootExists,
                contentLength: rootContent?.length || 0,
                consoleLogs: consoleLogs.length,
                pageErrors: pageErrors.length
            }
        };

    } catch (error) {
        console.error('❌ Browser test failed:', error.message);
        console.log('\n🔄 Falling back to HTTP checks...\n');
        return await fallbackHttpChecks();
    } finally {
        if (browser) {
            await browser.close();
        }
    }
}

async function fallbackHttpChecks() {
    const http = require('http');

    console.log('📡 Running HTTP-based checks...\n');

    try {
        const html = await new Promise((resolve, reject) => {
            http.get('http://localhost:3000', (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => resolve(data));
            }).on('error', reject);
        });

        console.log(`✓ Main page loads: ${html.length} characters`);
        console.log(`✓ Contains root div: ${html.includes('<div id="root">') ? 'YES' : 'NO'}`);

        const jsMatch = html.match(/src="([^"]*main\.[^"]*\.js)"/);
        if (jsMatch) {
            console.log(`✓ JavaScript bundle found: ${jsMatch[1]}`);

            const jsContent = await new Promise((resolve, reject) => {
                http.get(`http://localhost:3000${jsMatch[1]}`, (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => resolve(data));
                }).on('error', reject);
            });

            console.log(`✓ JS bundle size: ${jsContent.length} characters`);
            console.log(`✓ Contains React: ${jsContent.includes('React') ? 'YES' : 'NO'}`);
            console.log(`✓ Contains DashboardOptimized: ${jsContent.includes('DashboardOptimized') ? 'YES' : 'NO'}`);
        }

        return {
            success: true,
            details: { method: 'HTTP', htmlSize: html.length }
        };

    } catch (error) {
        console.error('❌ HTTP checks failed:', error.message);
        return { success: false, error: error.message };
    }
}

testFrontendMounting().then(result => {
    console.log('\n📊 Final Result:', result);
    process.exit(result.success ? 0 : 1);
}).catch(error => {
    console.error('🚨 Test script failed:', error);
    process.exit(1);
});