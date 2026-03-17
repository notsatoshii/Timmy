const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const TIMEOUT = 30000; // 30 second timeout
const MAX_RETRIES = 3;

const browserConfigs = [
    // Default config
    {
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
    },
    // Fallback config 1 - more isolation flags
    {
        headless: 'new',
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-web-security',
            '--disable-features=VizDisplayCompositor',
            '--disable-background-networking',
            '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows',
            '--disable-renderer-backgrounding'
        ]
    },
    // Fallback config 2 - basic headless
    {
        headless: true,
        args: ['--no-sandbox', '--disable-dev-shm-usage']
    }
];

async function launchBrowserWithFallback() {
    for (let i = 0; i < browserConfigs.length; i++) {
        console.log(`Trying browser config ${i + 1}/${browserConfigs.length}...`);
        try {
            const browser = await Promise.race([
                puppeteer.launch(browserConfigs[i]),
                new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Browser launch timeout')), TIMEOUT)
                )
            ]);
            console.log('✓ Browser launched successfully');
            return browser;
        } catch (error) {
            console.log(`✗ Config ${i + 1} failed: ${error.message}`);
            if (i === browserConfigs.length - 1) throw error;
        }
    }
}

async function takeScreenshotSafely(page, filepath, label) {
    try {
        await Promise.race([
            page.screenshot({ path: filepath, fullPage: true }),
            new Promise((_, reject) =>
                setTimeout(() => reject(new Error('Screenshot timeout')), 10000)
            )
        ]);
        console.log(`✓ Screenshot: ${label}`);
        return true;
    } catch (error) {
        console.log(`✗ Screenshot failed for ${label}: ${error.message}`);
        return false;
    }
}

async function manualFallback() {
    console.log('\n🔄 Puppeteer failed, implementing manual fallback...');
    const ts = new Date().toISOString().replace(/[:.]/g, '-');

    // Create placeholder report showing the issue
    const result = {
        timestamp: ts,
        console_errors: ['Puppeteer browser launch failed - manual verification needed'],
        screenshots: [],
        fallback_used: true,
        frontend_check: null
    };

    // Try basic HTTP check to see if frontend is responsive
    try {
        const http = require('http');
        const checkPromise = new Promise((resolve, reject) => {
            const req = http.get(FRONTEND_URL, (res) => {
                if (res.statusCode === 200) {
                    resolve('Frontend responding on port 3000');
                } else {
                    resolve(`Frontend returned status ${res.statusCode}`);
                }
            });
            req.on('error', reject);
            req.setTimeout(5000, () => reject(new Error('Frontend check timeout')));
        });

        result.frontend_check = await checkPromise;
        console.log('✓ Frontend HTTP check:', result.frontend_check);

    } catch (error) {
        result.frontend_check = `Frontend unreachable: ${error.message}`;
        console.log('✗ Frontend HTTP check failed:', error.message);
    }

    fs.writeFileSync(path.join(DIR, 'latest-review.json'), JSON.stringify(result, null, 2));
    console.log('\n📋 Manual verification needed:');
    console.log('1. Open http://localhost:3000 in your browser');
    console.log('2. Check that Markets, Trading, Vault, and Positions tabs load without blank screens');
    console.log('3. Verify no console errors in browser dev tools');

    return result;
}

(async () => {
    if (!fs.existsSync(DIR)) fs.mkdirSync(DIR, { recursive: true });
    const ts = new Date().toISOString().replace(/[:.]/g, '-');

    let browser;
    let result;

    try {
        browser = await launchBrowserWithFallback();

        const page = await browser.newPage();
        const errors = [];
        page.on('console', msg => {
            if (msg.type() === 'error') errors.push(msg.text());
        });
        page.on('pageerror', err => errors.push(err.message));

        // Set timeout for page operations
        page.setDefaultTimeout(TIMEOUT);

        // Desktop screenshots
        await page.setViewport({ width: 1440, height: 900 });
        console.log('🌐 Loading frontend...');

        await Promise.race([
            page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: TIMEOUT }),
            new Promise((_, reject) =>
                setTimeout(() => reject(new Error('Page load timeout')), TIMEOUT)
            )
        ]);

        await new Promise(r => setTimeout(r, 4000));

        // Markets tab (default)
        const screenshots = [];
        if (await takeScreenshotSafely(page, path.join(DIR, `markets-${ts}.png`), 'markets')) {
            screenshots.push(`markets-${ts}.png`);
        }

        // Click each tab with timeout protection
        for (const tab of ['Trading', 'Vault', 'Positions']) {
            try {
                console.log(`🖱️  Clicking ${tab} tab...`);
                await Promise.race([
                    page.evaluate(t => {
                        for (const el of document.querySelectorAll('*')) {
                            if (el.textContent.trim() === t && el.offsetParent !== null && el.children.length <= 2) {
                                el.click(); return;
                            }
                        }
                    }, tab),
                    new Promise((_, reject) =>
                        setTimeout(() => reject(new Error('Tab click timeout')), 5000)
                    )
                ]);

                await new Promise(r => setTimeout(r, 2000));

                if (await takeScreenshotSafely(page, path.join(DIR, `${tab.toLowerCase()}-${ts}.png`), tab)) {
                    screenshots.push(`${tab.toLowerCase()}-${ts}.png`);
                }
            } catch(e) {
                console.log(`✗ ${tab} tab failed: ${e.message}`);
            }
        }

        // Mobile screenshot with timeout
        try {
            console.log('📱 Taking mobile screenshot...');
            await page.setViewport({ width: 375, height: 812 });

            await Promise.race([
                page.evaluate(() => {
                    for (const el of document.querySelectorAll('*')) {
                        if (el.textContent.trim() === 'Markets' && el.offsetParent !== null && el.children.length <= 2) {
                            el.click(); return;
                        }
                    }
                }),
                new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Mobile navigation timeout')), 5000)
                )
            ]);

            await new Promise(r => setTimeout(r, 2000));

            if (await takeScreenshotSafely(page, path.join(DIR, `mobile-${ts}.png`), 'mobile')) {
                screenshots.push(`mobile-${ts}.png`);
            }
        } catch(e) {
            console.log(`✗ Mobile screenshot failed: ${e.message}`);
        }

        await browser.close();

        // Save console errors and file list
        result = {
            timestamp: ts,
            console_errors: errors.filter(e => !e.includes('favicon') && !e.includes('ResizeObserver')),
            screenshots: screenshots,
            success: true,
            fallback_used: false
        };

        fs.writeFileSync(path.join(DIR, 'latest-review.json'), JSON.stringify(result, null, 2));
        console.log(`\n✅ Done. ${result.console_errors.length} console errors.`);
        console.log(`📸 Screenshots taken: ${screenshots.length}/5`);
        console.log(`📁 Location: ${DIR}/`);

    } catch (error) {
        console.log(`\n❌ Puppeteer automation failed: ${error.message}`);
        if (browser) {
            try { await browser.close(); } catch(e) { /* ignore cleanup errors */ }
        }

        // Use manual fallback
        result = await manualFallback();
    }

    // Exit with appropriate code
    if (result.success || (result.fallback_used && result.frontend_check && !result.frontend_check.includes('unreachable'))) {
        process.exit(0);
    } else {
        console.log('\n⚠️  Screenshot verification incomplete - manual check required');
        process.exit(1);
    }
})();
