const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const SCREENSHOT_DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const REPORT_PATH = '/home/lever/lever-protocol/control-plane/visual-report.json';

async function verify() {
    if (!fs.existsSync(SCREENSHOT_DIR)) {
        fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
    }

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const report = { timestamp, checks: [], pass: 0, fail: 0 };

    let browser;
    try {
        console.log('Launching browser with default Puppeteer settings...');

        browser = await puppeteer.launch({
            headless: 'new',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
                '--disable-extensions',
                '--disable-background-timer-throttling',
                '--disable-backgrounding-occluded-windows',
                '--disable-renderer-backgrounding',
                '--disable-features=TranslateUI',
                '--disable-ipc-flooding-protection',
                '--no-first-run',
                '--no-default-browser-check',
                '--ignore-certificate-errors'
            ]
        });
    } catch (e) {
        console.error('FATAL: Cannot launch browser:', e.message);
        console.error('Install: apt-get install -y chromium-browser');
        console.error('Or: cd frontend/user-app && npm install puppeteer --save-dev');
        report.checks.push({ name: 'browser_launch', status: 'FAIL', detail: e.message });
        report.fail++;
        fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2));
        process.exit(1);
    }

    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });

    const consoleErrors = [];
    page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', err => consoleErrors.push(err.message));

    try {
        // Load page
        console.log('Loading frontend...');
        const response = await page.goto(FRONTEND_URL, {
            waitUntil: 'networkidle2',
            timeout: 30000
        });

        if (!response || response.status() !== 200) {
            report.checks.push({
                name: 'http_status',
                status: 'FAIL',
                detail: 'HTTP ' + (response ? response.status() : 'no response')
            });
            report.fail++;
        }

        // Wait for React to hydrate
        await new Promise(r => setTimeout(r, 4000));

        // Screenshot: main page
        const mainShot = path.join(SCREENSHOT_DIR, 'main-' + timestamp + '.png');
        await page.screenshot({ path: mainShot, fullPage: true });
        console.log('Screenshot saved:', mainShot);

        // CHECK 1: Page renders content (not black screen)
        const bodyText = await page.evaluate(() => document.body.innerText.trim());
        const hasContent = bodyText.length > 50;
        report.checks.push({
            name: 'page_renders',
            status: hasContent ? 'PASS' : 'FAIL',
            detail: hasContent ? bodyText.length + ' chars of content' : 'Page is blank (' + bodyText.length + ' chars)'
        });
        hasContent ? report.pass++ : report.fail++;

        // CHECK 2: LEVER branding
        const hasLever = bodyText.includes('LEVER');
        report.checks.push({
            name: 'branding',
            status: hasLever ? 'PASS' : 'FAIL',
            detail: hasLever ? 'LEVER branding found' : 'No LEVER branding'
        });
        hasLever ? report.pass++ : report.fail++;

        // CHECK 3: Stats banner TVL
        const tvlValue = await page.evaluate(() => {
            // Find the element that says "Total TVL" and get its sibling/nearby value
            const all = document.querySelectorAll('*');
            for (const el of all) {
                if (el.childNodes.length === 1 &&
                    el.textContent.trim() === 'Total TVL') {
                    // Look at parent's text for the dollar value
                    const parent = el.parentElement;
                    if (parent) {
                        const match = parent.innerText.match(/\$[\d,.]+/);
                        if (match) return match[0];
                    }
                }
            }
            return 'NOT_FOUND';
        });
        const tvlOk = tvlValue !== 'NOT_FOUND' && tvlValue !== '$0.00';
        report.checks.push({
            name: 'tvl_display',
            status: tvlOk ? 'PASS' : 'FAIL',
            detail: 'TVL shows: ' + tvlValue
        });
        tvlOk ? report.pass++ : report.fail++;

        // CHECK 4: Data source (Live Oracle vs Demo Fallback)
        const isLive = bodyText.includes('Live Oracle');
        const isFallback = bodyText.includes('Demo Fallback');
        report.checks.push({
            name: 'data_source',
            status: isLive ? 'PASS' : 'FAIL',
            detail: isLive ? 'Live Oracle' : (isFallback ? 'Demo Fallback (not live)' : 'Unknown source')
        });
        isLive ? report.pass++ : report.fail++;

        // CHECK 5: Market cards with non-zero prices
        const marketPrices = await page.evaluate(() => {
            const results = [];
            const all = document.querySelectorAll('*');
            for (const el of all) {
                const text = el.textContent.trim();
                // Match price patterns like "88.0¢" or "35.0¢"
                if (/^\d+\.\d+¢$/.test(text) && el.children.length === 0) {
                    results.push(text);
                }
            }
            return results;
        });
        const nonZeroPrices = marketPrices.filter(p => !p.startsWith('0.0'));
        report.checks.push({
            name: 'market_prices',
            status: nonZeroPrices.length >= 3 ? 'PASS' : 'FAIL',
            detail: nonZeroPrices.length + ' non-zero prices found (' + marketPrices.length + ' total): ' + nonZeroPrices.slice(0, 5).join(', ')
        });
        nonZeroPrices.length >= 3 ? report.pass++ : report.fail++;

        // CHECK 6: Wallet/connect button
        const walletText = await page.evaluate(() => {
            const buttons = document.querySelectorAll('button');
            for (const btn of buttons) {
                const t = btn.textContent.trim();
                if (t.includes('Connect') || t.includes('Loading') ||
                    t.includes('Wallet') || t.includes('Demo')) {
                    return t;
                }
            }
            return 'NOT_FOUND';
        });
        const walletOk = (walletText.includes('Connect') || walletText.includes('Demo')) &&
                          !walletText.includes('Loading');
        report.checks.push({
            name: 'wallet_button',
            status: walletOk ? 'PASS' : 'FAIL',
            detail: 'Button: "' + walletText + '"'
        });
        walletOk ? report.pass++ : report.fail++;

        // CHECK 7-9: Each tab renders
        const tabs = ['Trading', 'Vault', 'Positions'];
        for (const tab of tabs) {
            try {
                // Click tab
                await page.evaluate((tabName) => {
                    const elements = document.querySelectorAll('*');
                    for (const el of elements) {
                        if (el.textContent.trim() === tabName &&
                            el.offsetParent !== null &&
                            el.children.length <= 2) {
                            el.click();
                            return true;
                        }
                    }
                    return false;
                }, tab);

                await new Promise(r => setTimeout(r, 2000));

                // Screenshot
                const tabShot = path.join(SCREENSHOT_DIR, tab.toLowerCase() + '-' + timestamp + '.png');
                await page.screenshot({ path: tabShot, fullPage: true });

                // Check content
                const content = await page.evaluate(() => document.body.innerText.trim().length);
                report.checks.push({
                    name: 'tab_' + tab.toLowerCase(),
                    status: content > 100 ? 'PASS' : 'FAIL',
                    detail: content + ' chars rendered'
                });
                content > 100 ? report.pass++ : report.fail++;
            } catch (e) {
                report.checks.push({
                    name: 'tab_' + tab.toLowerCase(),
                    status: 'FAIL',
                    detail: 'Error: ' + e.message
                });
                report.fail++;
            }
        }

        // CHECK 10: Console errors
        const criticalErrors = consoleErrors.filter(e =>
            !e.includes('favicon') &&
            !e.includes('manifest') &&
            !e.includes('ResizeObserver')
        );
        report.checks.push({
            name: 'console_errors',
            status: criticalErrors.length === 0 ? 'PASS' : 'FAIL',
            detail: criticalErrors.length === 0 ?
                'No critical console errors' :
                criticalErrors.length + ' errors: ' + criticalErrors.slice(0, 3).join(' | ')
        });
        criticalErrors.length === 0 ? report.pass++ : report.fail++;

    } catch (e) {
        report.checks.push({
            name: 'page_load',
            status: 'FAIL',
            detail: e.message
        });
        report.fail++;
    }

    await browser.close();

    // Write report
    fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2));

    // Print summary
    console.log('');
    console.log('=== VISUAL VERIFICATION: ' + report.pass + ' passed, ' + report.fail + ' failed ===');
    report.checks.forEach(c => {
        console.log('  ' + c.status + ': ' + c.name + ' — ' + c.detail);
    });
    console.log('');
    console.log('Screenshots: ' + SCREENSHOT_DIR);
    console.log('Report: ' + REPORT_PATH);

    process.exit(report.fail > 0 ? 1 : 0);
}

verify().catch(e => {
    console.error('Fatal:', e);
    process.exit(1);
});
