const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const DIR = '/home/lever/lever-protocol/control-plane/screenshots';

(async () => {
    if (!fs.existsSync(DIR)) fs.mkdirSync(DIR, { recursive: true });
    const ts = new Date().toISOString().replace(/[:.]/g, '-');

    const browser = await puppeteer.launch({
        headless: 'new',
        executablePath: '/usr/bin/chromium-browser',
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
    });

    const page = await browser.newPage();
    const errors = [];
    page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
    page.on('pageerror', err => errors.push(err.message));

    // Desktop screenshots
    await page.setViewport({ width: 1440, height: 900 });
    await page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 4000));

    // Markets tab (default)
    await page.screenshot({ path: path.join(DIR, `markets-${ts}.png`), fullPage: true });
    console.log('Screenshot: markets');

    // Click each tab
    for (const tab of ['Trading', 'Vault', 'Positions']) {
        try {
            await page.evaluate(t => {
                for (const el of document.querySelectorAll('*')) {
                    if (el.textContent.trim() === t && el.offsetParent !== null && el.children.length <= 2) {
                        el.click(); return;
                    }
                }
            }, tab);
            await new Promise(r => setTimeout(r, 2000));
            await page.screenshot({ path: path.join(DIR, `${tab.toLowerCase()}-${ts}.png`), fullPage: true });
            console.log('Screenshot: ' + tab);
        } catch(e) { console.error(tab + ' failed:', e.message); }
    }

    // Mobile
    await page.setViewport({ width: 375, height: 812 });
    await page.evaluate(() => {
        for (const el of document.querySelectorAll('*')) {
            if (el.textContent.trim() === 'Markets' && el.offsetParent !== null && el.children.length <= 2) {
                el.click(); return;
            }
        }
    });
    await new Promise(r => setTimeout(r, 2000));
    await page.screenshot({ path: path.join(DIR, `mobile-${ts}.png`), fullPage: true });
    console.log('Screenshot: mobile');

    await browser.close();

    // Save console errors and file list
    const result = {
        timestamp: ts,
        console_errors: errors.filter(e => !e.includes('favicon') && !e.includes('ResizeObserver')),
        screenshots: [
            `markets-${ts}.png`,
            `trading-${ts}.png`,
            `vault-${ts}.png`,
            `positions-${ts}.png`,
            `mobile-${ts}.png`
        ]
    };
    fs.writeFileSync(path.join(DIR, `latest-review.json`), JSON.stringify(result, null, 2));
    console.log(`\nDone. ${result.console_errors.length} console errors.`);
    console.log(`Screenshots: ${DIR}/*-${ts}.png`);
})();
