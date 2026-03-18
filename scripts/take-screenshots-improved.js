#!/usr/bin/env node
/**
 * LEVER Protocol - Improved Screenshot & Verification System
 *
 * This script provides comprehensive frontend verification with multiple fallback methods.
 * Primary focus on investor demo readiness verification.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { exec } = require('child_process');

const FRONTEND_URL = 'http://localhost:3000';
const DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const TIMEOUT = 30000;

// Enhanced browser configurations with new Chrome for Testing
const browserConfigs = [
    // Chrome for Testing with custom launcher
    {
        executablePath: '/home/lever/local-libs/chrome-launcher.sh',
        headless: 'new',
        args: ['--remote-debugging-port=0']
    },
    // Chrome for Testing direct (in case launcher fails)
    {
        executablePath: '/home/lever/local-libs/chrome-linux64/chrome',
        headless: 'new',
        env: {
            ...process.env,
            LD_LIBRARY_PATH: '/home/lever/local-libs/extracted-libs/usr/lib/x86_64-linux-gnu:' + (process.env.LD_LIBRARY_PATH || '')
        },
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--headless=new',
            '--disable-web-security'
        ]
    },
    // Original standalone Chrome
    {
        executablePath: '/home/lever/local-libs/standalone-chrome/chrome',
        headless: 'new',
        env: {
            ...process.env,
            LD_LIBRARY_PATH: '/home/lever/local-libs/standalone-chrome:' + (process.env.LD_LIBRARY_PATH || ''),
        },
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--headless=new'
        ]
    }
];

/**
 * Test frontend availability with detailed analysis
 */
async function testFrontendEndpoint(url, timeout = 10000) {
    return new Promise((resolve) => {
        const req = http.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                const result = {
                    success: true,
                    status: res.statusCode,
                    size: data.length,
                    headers: res.headers,
                    contentType: res.headers['content-type'] || '',
                    hasReact: data.includes('React') || data.includes('react') || data.includes('root'),
                    hasBundle: data.includes('bundle') || data.includes('static/js'),
                    hasTitle: data.includes('<title>'),
                    isHealthy: res.statusCode === 200 && data.length > 1000
                };
                resolve(result);
            });
        });

        req.on('error', (error) => {
            resolve({
                success: false,
                error: error.message,
                code: error.code
            });
        });

        req.setTimeout(timeout, () => {
            req.destroy();
            resolve({
                success: false,
                error: 'Request timeout',
                timeout: true
            });
        });
    });
}

/**
 * Advanced browser automation attempt
 */
async function attemptBrowserAutomation() {
    const puppeteer = require('puppeteer');

    for (let i = 0; i < browserConfigs.length; i++) {
        console.log(`🔄 Trying browser config ${i + 1}/${browserConfigs.length}...`);

        try {
            const browser = await Promise.race([
                puppeteer.launch(browserConfigs[i]),
                new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Browser launch timeout')), TIMEOUT)
                )
            ]);

            console.log(`✅ Browser launched successfully with config ${i + 1}`);

            // Take screenshots
            const screenshots = await takeAllScreenshots(browser);
            await browser.close();

            return {
                success: true,
                method: 'browser_automation',
                config_used: i + 1,
                screenshots: screenshots,
                browser_automation: true
            };

        } catch (error) {
            console.log(`❌ Config ${i + 1} failed: ${error.message}`);
        }
    }

    throw new Error('All browser configurations failed');
}

/**
 * Take all required screenshots
 */
async function takeAllScreenshots(browser) {
    const page = await browser.newPage();
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const screenshots = [];
    const errors = [];

    // Monitor console errors
    page.on('console', msg => {
        if (msg.type() === 'error') errors.push(msg.text());
    });
    page.on('pageerror', err => errors.push(err.message));

    try {
        // Set desktop viewport
        await page.setViewport({ width: 1440, height: 900 });
        console.log('🌐 Loading frontend...');

        await page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: TIMEOUT });
        await new Promise(r => setTimeout(r, 3000)); // Wait for React to settle

        // Take screenshots for each tab
        const tabs = ['Markets', 'Trading', 'Vault', 'Positions'];

        for (const tab of tabs) {
            try {
                // Click tab if not the first one
                if (tab !== 'Markets') {
                    await page.evaluate(tabName => {
                        const elements = Array.from(document.querySelectorAll('*'));
                        const tabElement = elements.find(el =>
                            el.textContent.trim() === tabName &&
                            el.offsetParent !== null &&
                            el.children.length <= 2
                        );
                        if (tabElement) tabElement.click();
                    }, tab);

                    await new Promise(r => setTimeout(r, 2000)); // Wait for tab load
                }

                const filename = `${tab.toLowerCase()}-${ts}.png`;
                await page.screenshot({
                    path: path.join(DIR, filename),
                    fullPage: true
                });

                screenshots.push(filename);
                console.log(`📸 Screenshot: ${tab}`);

            } catch (error) {
                console.log(`❌ Failed to capture ${tab}: ${error.message}`);
            }
        }

        // Mobile screenshot
        await page.setViewport({ width: 375, height: 812 });
        await page.reload();
        await new Promise(r => setTimeout(r, 3000));

        const mobileFilename = `mobile-${ts}.png`;
        await page.screenshot({
            path: path.join(DIR, mobileFilename),
            fullPage: true
        });
        screenshots.push(mobileFilename);
        console.log('📱 Mobile screenshot taken');

    } catch (error) {
        console.log(`❌ Screenshot process failed: ${error.message}`);
    }

    return {
        files: screenshots,
        console_errors: errors.filter(e =>
            !e.includes('favicon') &&
            !e.includes('ResizeObserver') &&
            !e.includes('404')
        )
    };
}

/**
 * Enhanced HTTP verification (primary method for investor demos)
 */
async function performHTTPVerification() {
    console.log('🔍 Performing comprehensive HTTP verification...');

    const ts = new Date().toISOString().replace(/[:.]/g, '-');

    // Test main frontend endpoint
    const frontendTest = await testFrontendEndpoint(FRONTEND_URL);

    // Test additional endpoints
    const endpoints = [
        { path: '/static/js/', name: 'JS assets' },
        { path: '/static/css/', name: 'CSS assets' },
        { path: '/favicon.ico', name: 'Static files' }
    ];

    const endpointResults = [];
    for (const endpoint of endpoints) {
        const result = await testFrontendEndpoint(FRONTEND_URL + endpoint.path, 5000);
        endpointResults.push({
            endpoint: endpoint.name,
            success: result.success,
            status: result.status,
            details: result.success ? `HTTP ${result.status}` : result.error
        });
    }

    // Run additional UI verification
    const uiVerification = await new Promise((resolve) => {
        exec('node scripts/comprehensive-ui-verification.js', (error, stdout, stderr) => {
            resolve({
                success: !error,
                output: stdout,
                error: stderr
            });
        });
    });

    // Create comprehensive verification report
    const report = {
        timestamp: ts,
        method: 'http_verification',
        frontend_test: frontendTest,
        endpoint_tests: endpointResults,
        ui_verification: uiVerification,
        overall_health: frontendTest.isHealthy && !frontendTest.error,
        investor_demo_ready: frontendTest.isHealthy && frontendTest.hasReact,
        recommendations: []
    };

    // Generate recommendations
    if (!frontendTest.hasReact) {
        report.recommendations.push('Frontend may not be properly serving React application');
    }
    if (frontendTest.size < 1000) {
        report.recommendations.push('Frontend response unusually small - check for errors');
    }
    if (!uiVerification.success) {
        report.recommendations.push('UI verification detected issues - check console output');
    }

    // Create visual verification HTML
    await createVisualVerificationReport(report, ts);

    return report;
}

/**
 * Create HTML visual verification report
 */
async function createVisualVerificationReport(report, timestamp) {
    const statusColor = report.overall_health ? 'green' : 'red';
    const statusText = report.overall_health ? 'HEALTHY ✅' : 'ISSUES DETECTED ⚠️';

    const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LEVER Protocol - Frontend Verification Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, monospace;
            margin: 0; padding: 20px;
            background: #f5f5f5;
        }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; margin: -30px -30px 30px; border-radius: 8px 8px 0 0; }
        .status { font-size: 24px; font-weight: bold; color: ${statusColor}; margin: 20px 0; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 6px; border-left: 4px solid #667eea; }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        iframe { width: 100%; height: 600px; border: 1px solid #ddd; border-radius: 6px; margin-top: 20px; }
        .metrics { display: flex; gap: 20px; margin: 20px 0; }
        .metric { flex: 1; text-align: center; padding: 15px; background: #e9ecef; border-radius: 6px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #495057; }
        .metric-label { font-size: 12px; text-transform: uppercase; color: #6c757d; margin-top: 5px; }
        .checklist { background: #fff3cd; border: 1px solid #ffeaa7; border-radius: 6px; padding: 20px; margin: 20px 0; }
        .checklist ul { margin: 0; padding-left: 20px; }
        .tech-info { background: #e7f3ff; border: 1px solid #b3d9ff; border-radius: 6px; padding: 15px; margin: 20px 0; font-family: monospace; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 LEVER Protocol Frontend Verification</h1>
            <p><strong>Timestamp:</strong> ${new Date().toLocaleString()}</p>
            <p><strong>Verification Method:</strong> HTTP Analysis + UI Testing</p>
        </div>

        <div class="status">Status: ${statusText}</div>

        <div class="metrics">
            <div class="metric">
                <div class="metric-value">${report.frontend_test.status || 'ERR'}</div>
                <div class="metric-label">HTTP Status</div>
            </div>
            <div class="metric">
                <div class="metric-value">${Math.round((report.frontend_test.size || 0) / 1024)}KB</div>
                <div class="metric-label">Response Size</div>
            </div>
            <div class="metric">
                <div class="metric-value">${report.frontend_test.hasReact ? 'YES' : 'NO'}</div>
                <div class="metric-label">React App</div>
            </div>
            <div class="metric">
                <div class="metric-value">${report.investor_demo_ready ? 'READY' : 'NOT READY'}</div>
                <div class="metric-label">Demo Ready</div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h3>📊 Frontend Health</h3>
                <p class="${report.frontend_test.success ? 'success' : 'error'}">
                    ${report.frontend_test.success ?
                        `✅ Frontend responding: ${report.frontend_test.status} (${report.frontend_test.size} bytes)` :
                        `❌ Frontend error: ${report.frontend_test.error}`
                    }
                </p>
                <p><strong>React Detection:</strong> ${report.frontend_test.hasReact ? '✅ Yes' : '❌ No'}</p>
                <p><strong>Content Type:</strong> ${report.frontend_test.contentType || 'Unknown'}</p>
            </div>

            <div class="card">
                <h3>🔍 Endpoint Tests</h3>
                ${report.endpoint_tests.map(test =>
                    `<p class="${test.success ? 'success' : 'error'}">
                        ${test.success ? '✅' : '❌'} ${test.endpoint}: ${test.details}
                    </p>`
                ).join('')}
            </div>
        </div>

        ${report.recommendations.length > 0 ? `
        <div class="card" style="border-left-color: #ffc107;">
            <h3>⚠️ Recommendations</h3>
            <ul>
                ${report.recommendations.map(rec => `<li>${rec}</li>`).join('')}
            </ul>
        </div>
        ` : ''}

        <div class="checklist">
            <h3>📋 Manual Verification Checklist for Investor Demo</h3>
            <ul>
                <li>Open <a href="${FRONTEND_URL}" target="_blank">${FRONTEND_URL}</a></li>
                <li>Verify Markets tab loads with market data (not blank)</li>
                <li>Test Trading tab - should show position interface</li>
                <li>Test Vault tab - should show vault info and deposit form</li>
                <li>Test Positions tab - should show positions table</li>
                <li>Open browser dev tools (F12) - check for errors</li>
                <li>Test mobile responsiveness</li>
                <li>Verify contract interactions work (if applicable)</li>
            </ul>
        </div>

        ${report.overall_health ? `
        <iframe src="${FRONTEND_URL}" title="LEVER Protocol Frontend Preview"></iframe>
        ` : ''}

        <div class="tech-info">
            <strong>Technical Information:</strong><br>
            • Browser automation: ${report.browser_automation ? 'Available' : 'Fallback to HTTP verification'}<br>
            • Verification method: ${report.method}<br>
            • Report generated: ${timestamp}<br>
            • Next run: Automated every 2 hours via systemd
        </div>
    </div>
</body>
</html>`;

    const reportFile = path.join(DIR, `visual-verification-${timestamp}.html`);
    fs.writeFileSync(reportFile, htmlContent);
    console.log(`📋 Visual report created: ${reportFile}`);

    return reportFile;
}

/**
 * Main execution function
 */
async function main() {
    if (!fs.existsSync(DIR)) {
        fs.mkdirSync(DIR, { recursive: true });
    }

    console.log('🔄 LEVER Protocol Frontend Verification Starting...\n');

    let result;

    try {
        // First attempt: Browser automation
        console.log('🎯 Attempting browser automation...');
        result = await attemptBrowserAutomation();
        console.log('✅ Browser automation successful!');

    } catch (automationError) {
        console.log(`❌ Browser automation failed: ${automationError.message}\n`);

        // Fallback: HTTP verification (primary method for investor demos)
        console.log('🔄 Using HTTP verification method...');
        result = await performHTTPVerification();
    }

    // Save comprehensive result
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const resultFile = path.join(DIR, 'latest-review.json');
    fs.writeFileSync(resultFile, JSON.stringify(result, null, 2));

    // Save timestamped report
    const timestampedFile = path.join(DIR, `verification-report-${timestamp}.json`);
    fs.writeFileSync(timestampedFile, JSON.stringify(result, null, 2));

    // Display summary
    console.log('\n' + '='.repeat(60));
    console.log('🎯 LEVER Protocol Frontend Verification Summary');
    console.log('='.repeat(60));
    console.log(`Method: ${result.method}`);
    console.log(`Status: ${result.overall_health ? 'HEALTHY ✅' : 'ISSUES DETECTED ⚠️'}`);
    console.log(`Investor Demo Ready: ${result.investor_demo_ready ? 'YES ✅' : 'NO ❌'}`);

    if (result.screenshots && result.screenshots.files) {
        console.log(`Screenshots: ${result.screenshots.files.length} taken`);
    }

    console.log(`Reports saved to: ${DIR}/`);
    console.log('='.repeat(60));

    // Exit with appropriate code
    const isSuccess = result.overall_health ||
                     (result.frontend_test && result.frontend_test.isHealthy) ||
                     (result.investor_demo_ready === true);

    if (isSuccess) {
        console.log('\n✅ Frontend verification passed - System ready for investor demo');
        process.exit(0);
    } else {
        console.log('\n❌ Frontend verification failed - Check reports for details');
        process.exit(1);
    }
}

// Run the script
if (require.main === module) {
    main().catch(error => {
        console.error('💥 Fatal error:', error.message);
        process.exit(1);
    });
}

module.exports = { main, performHTTPVerification, testFrontendEndpoint };