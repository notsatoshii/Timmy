const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const SCREENSHOT_DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const REPORT_PATH = '/home/lever/lever-protocol/control-plane/visual-report.json';

async function verify() {
    if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const report = { timestamp, checks: [], pass: 0, fail: 0 };
    
    const browser = await puppeteer.launch({
        headless: 'new',
        executablePath: '/usr/bin/chromium-browser',
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
    });
    
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    
    // Capture console errors
    const consoleErrors = [];
    page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', err => consoleErrors.push(err.message));

    try {
        // 1. Load page
        console.log('Loading frontend...');
        await page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: 30000 });
        await page.waitForTimeout(3000); // let React hydrate
        
        // 2. Screenshot: Full page
        const mainShot = path.join(SCREENSHOT_DIR, `main-${timestamp}.png`);
        await page.screenshot({ path: mainShot, fullPage: true });
        console.log('Screenshot saved:', mainShot);
        
        // 3. Check: Is it a black/empty screen?
        const bodyText = await page.evaluate(() => document.body.innerText.trim());
        if (bodyText.length < 20) {
            report.checks.push({ name: 'page_renders', status: 'FAIL', detail: 'Page is blank or near-blank' });
            report.fail++;
        } else {
            report.checks.push({ name: 'page_renders', status: 'PASS', detail: `${bodyText.length} chars of content` });
            report.pass++;
        }
        
        // 4. Check: LEVER branding present?
        const hasLever = await page.evaluate(() => document.body.innerText.includes('LEVER'));
        report.checks.push({ 
            name: 'branding', 
            status: hasLever ? 'PASS' : 'FAIL',
            detail: hasLever ? 'LEVER branding found' : 'No LEVER branding'
        });
        hasLever ? report.pass++ : report.fail++;
        
        // 5. Check: Stats banner — does TVL show > $0?
        const tvlText = await page.evaluate(() => {
            const els = [...document.querySelectorAll('*')];
            const tvlEl = els.find(el => el.textContent.includes('Total TVL'));
            if (!tvlEl) return 'NOT_FOUND';
            // Get the value near it
            const parent = tvlEl.closest('div') || tvlEl.parentElement;
            return parent ? parent.innerText : 'NOT_FOUND';
        });
        const tvlIsZero = tvlText.includes('$0.00') || tvlText === 'NOT_FOUND';
        report.checks.push({
            name: 'tvl_display',
            status: tvlIsZero ? 'FAIL' : 'PASS',
            detail: tvlIsZero ? `TVL shows zero or not found: ${tvlText}` : `TVL showing: ${tvlText}`
        });
        tvlIsZero ? report.fail++ : report.pass++;
        
        // 6. Check: Markets — "Live Oracle" vs "Demo Fallback"
        const dataSource = await page.evaluate(() => {
            const text = document.body.innerText;
            if (text.includes('Live Oracle')) return 'live';
            if (text.includes('Demo Fallback')) return 'fallback';
            return 'unknown';
        });
        report.checks.push({
            name: 'data_source',
            status: dataSource === 'live' ? 'PASS' : 'FAIL',
            detail: dataSource === 'live' ? 'Reading from Live Oracle' : `Data source: ${dataSource}`
        });
        dataSource === 'live' ? report.pass++ : report.fail++;
        
        // 7. Check: Market cards show non-zero prices
        const prices = await page.evaluate(() => {
            const priceEls = [...document.querySelectorAll('*')].filter(el => 
                el.textContent.match(/^\d+\.\d+¢$/) && el.children.length === 0
            );
            return priceEls.map(el => el.textContent);
        });
        const nonZeroPrices = prices.filter(p => !p.startsWith('0.0'));
        report.checks.push({
            name: 'market_prices',
            status: nonZeroPrices.length >= 3 ? 'PASS' : 'FAIL',
            detail: `${nonZeroPrices.length} markets with non-zero prices out of ${prices.length} total`
        });
        nonZeroPrices.length >= 3 ? report.pass++ : report.fail++;
        
        // 8. Check: Wallet button exists and doesn't say "Loading..." forever
        const walletBtn = await page.evaluate(() => {
            const btns = [...document.querySelectorAll('button')];
            const wallet = btns.find(b => 
                b.textContent.includes('Connect') || 
                b.textContent.includes('Loading') ||
                b.textContent.includes('Wallet')
            );
            return wallet ? wallet.textContent.trim() : 'NOT_FOUND';
        });
        const walletOk = walletBtn.includes('Connect') && !walletBtn.includes('Loading');
        report.checks.push({
            name: 'wallet_button',
            status: walletOk ? 'PASS' : 'FAIL',
            detail: `Button text: "${walletBtn}"`
        });
        walletOk ? report.pass++ : report.fail++;
        
        // 9. Check: Each tab renders content
        const tabs = ['Trading', 'Vault', 'Positions'];
        for (const tab of tabs) {
            try {
                await page.evaluate((t) => {
                    const el = [...document.querySelectorAll('*')].find(e => 
                        e.textContent.trim() === t && e.offsetParent !== null
                    );
                    if (el) el.click();
                }, tab);
                await page.waitForTimeout(1500);
                
                const tabShot = path.join(SCREENSHOT_DIR, `${tab.toLowerCase()}-${timestamp}.png`);
                await page.screenshot({ path: tabShot, fullPage: true });
                
                const tabContent = await page.evaluate(() => document.body.innerText.length);
                report.checks.push({
                    name: `tab_${tab.toLowerCase()}`,
                    status: tabContent > 50 ? 'PASS' : 'FAIL',
                    detail: `${tabContent} chars of content`
                });
                tabContent > 50 ? report.pass++ : report.fail++;
            } catch (e) {
                report.checks.push({
                    name: `tab_${tab.toLowerCase()}`,
                    status: 'FAIL',
                    detail: e.message
                });
                report.fail++;
            }
        }
        
        // 10. Console errors
        report.checks.push({
            name: 'console_errors',
            status: consoleErrors.length === 0 ? 'PASS' : 'FAIL',
            detail: consoleErrors.length === 0 ? 'No console errors' : `${consoleErrors.length} errors: ${consoleErrors.slice(0,3).join(' | ')}`
        });
        consoleErrors.length === 0 ? report.pass++ : report.fail++;
        
    } catch (e) {
        report.checks.push({ name: 'page_load', status: 'FAIL', detail: e.message });
        report.fail++;
    }
    
    await browser.close();
    
    // Write report
    fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2));
    
    // Print summary
    console.log(`\n=== VISUAL VERIFICATION: ${report.pass} passed, ${report.fail} failed ===`);
    report.checks.forEach(c => console.log(`  ${c.status}: ${c.name} — ${c.detail}`));
    
    // Exit code
    process.exit(report.fail > 0 ? 1 : 0);
}

verify().catch(e => {
    console.error('Fatal:', e);
    process.exit(1);
});
