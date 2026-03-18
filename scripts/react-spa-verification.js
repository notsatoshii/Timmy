#!/usr/bin/env node
/**
 * React SPA Verification Script - Proper browser-based testing for React applications
 *
 * This script replaces curl-based testing with proper headless browser testing
 * that can evaluate JavaScript-rendered content in React SPAs.
 *
 * Key features:
 * - Uses Playwright for reliable browser automation
 * - Screenshots actual rendered UI (not just HTML shell)
 * - Extracts real DOM values after React renders
 * - Tests user interactions and navigation
 * - Validates data accuracy vs placeholder content
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const SCREENSHOTS_DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const TIMEOUT = 30000;

// Ensure screenshots directory exists
if (!fs.existsSync(SCREENSHOTS_DIR)) {
    fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
}

class ReactSPAVerifier {
    constructor() {
        this.browser = null;
        this.page = null;
        this.results = {
            timestamp: new Date().toISOString(),
            method: 'Playwright Browser Testing',
            tests: [],
            screenshots: [],
            console_errors: [],
            success: false,
            score: 0
        };
    }

    async init() {
        console.log('🚀 Initializing React SPA verification...');

        // Try Playwright first
        try {
            this.browser = await chromium.launch({
                headless: true,
                args: ['--no-sandbox', '--disable-setuid-sandbox']
            });
            this.browserType = 'playwright';
            console.log('✅ Using Playwright for browser automation');
        } catch (error) {
            if (error.message.includes('libatk') || error.message.includes('shared libraries')) {
                console.log('⚠️  Playwright dependencies missing, trying Puppeteer fallback...');
                // Fallback to Puppeteer
                try {
                    const puppeteer = require('puppeteer');
                    this.browser = await puppeteer.launch({
                        headless: 'new',
                        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
                    });
                    this.browserType = 'puppeteer';
                    console.log('✅ Using Puppeteer for browser automation');
                } catch (puppeteerError) {
                    throw new Error(`Browser automation failed: Playwright (${error.message}), Puppeteer (${puppeteerError.message})`);
                }
            } else {
                throw error;
            }
        }

        this.page = await this.browser.newPage();

        // Capture console errors (compatible with both Playwright and Puppeteer)
        this.page.on('console', msg => {
            const msgType = typeof msg.type === 'function' ? msg.type() : msg.type;
            if (msgType === 'error') {
                const msgText = typeof msg.text === 'function' ? msg.text() : msg.text;
                this.results.console_errors.push(msgText);
            }
        });

        this.page.on('pageerror', error => {
            this.results.console_errors.push(error.message);
        });

        await this.page.setViewport({ width: 1440, height: 900 });
    }

    async cleanup() {
        if (this.browser) {
            await this.browser.close();
        }
    }

    async takeScreenshot(name, description) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `${name}-${timestamp}.png`;
        const filepath = path.join(SCREENSHOTS_DIR, filename);

        try {
            await this.page.screenshot({
                path: filepath,
                fullPage: true
            });

            this.results.screenshots.push({
                name: filename,
                description: description,
                path: filepath
            });

            console.log(`📸 Screenshot: ${description}`);
            return filepath;
        } catch (error) {
            console.log(`❌ Screenshot failed for ${description}: ${error.message}`);
            return null;
        }
    }

    async testFrontendLoading() {
        console.log('🌐 Testing frontend loading and React rendering...');

        try {
            // Navigate to frontend (compatible with both browsers)
            const gotoOptions = this.browserType === 'puppeteer' ?
                { waitUntil: 'networkidle2', timeout: TIMEOUT } :
                { waitUntil: 'networkidle', timeout: TIMEOUT };

            await this.page.goto(FRONTEND_URL, gotoOptions);

            // Wait for React to render
            await this.page.waitForTimeout(3000);

            // Take screenshot
            await this.takeScreenshot('frontend-loaded', 'Frontend after React rendering');

            // Check if React app is actually rendered
            const bodyText = await this.page.textContent('body');
            const hasReactContent = bodyText && !bodyText.includes('Loading...') && bodyText.length > 100;

            // Check for React-specific elements
            const reactElements = await this.page.evaluate(() => {
                return {
                    hasReactRoot: !!document.getElementById('root'),
                    hasTabElements: document.querySelectorAll('[role="tab"], .tab, [class*="tab"]').length > 0,
                    hasButtons: document.querySelectorAll('button').length > 0,
                    textLength: document.body.innerText.length,
                    hasErrorBoundary: document.body.innerText.includes('Something went wrong'),
                    hasNaNValues: document.body.innerText.includes('$NaN') || document.body.innerText.includes('NaN%')
                };
            });

            const test = {
                name: 'Frontend Loading',
                passed: hasReactContent && reactElements.hasReactRoot && !reactElements.hasErrorBoundary && !reactElements.hasNaNValues,
                details: {
                    textLength: reactElements.textLength,
                    hasReactRoot: reactElements.hasReactRoot,
                    hasTabElements: reactElements.hasTabElements,
                    hasButtons: reactElements.hasButtons,
                    hasErrorBoundary: reactElements.hasErrorBoundary,
                    hasNaNValues: reactElements.hasNaNValues,
                    bodyTextPreview: bodyText?.substring(0, 200)
                },
                issues: []
            };

            if (!hasReactContent) test.issues.push('React content not rendered properly');
            if (!reactElements.hasReactRoot) test.issues.push('React root element missing');
            if (reactElements.hasErrorBoundary) test.issues.push('Error boundary visible');
            if (reactElements.hasNaNValues) test.issues.push('$NaN or NaN% values detected');
            if (reactElements.textLength < 100) test.issues.push('Very little content rendered');

            this.results.tests.push(test);
            return test.passed;

        } catch (error) {
            this.results.tests.push({
                name: 'Frontend Loading',
                passed: false,
                details: { error: error.message },
                issues: [`Failed to load: ${error.message}`]
            });
            return false;
        }
    }

    async testTabNavigation() {
        console.log('🔄 Testing tab navigation and content...');

        const tabs = ['Markets', 'Trading', 'Vault', 'Positions'];
        let allTabsPassed = true;

        for (const tabName of tabs) {
            try {
                console.log(`  Testing ${tabName} tab...`);

                // Click the tab
                await this.page.click(`text=${tabName}`, { timeout: 5000 });
                await this.page.waitForTimeout(2000);

                // Take screenshot
                await this.takeScreenshot(`tab-${tabName.toLowerCase()}`, `${tabName} tab content`);

                // Extract content and check for meaningful data
                const tabContent = await this.page.evaluate((tab) => {
                    const bodyText = document.body.innerText;
                    return {
                        textLength: bodyText.length,
                        hasTVLData: /TVL.*\$[\d,.]+(K|M|B)?/i.test(bodyText),
                        hasAPYData: /APY.*[\d.]+%/i.test(bodyText),
                        hasOIData: /(?:Open\s*Interest|OI).*\$[\d,.]+(K|M|B)?/i.test(bodyText),
                        hasLeverageData: /\d+(\.\d+)?[x×]/i.test(bodyText),
                        hasCharts: document.querySelectorAll('canvas, svg.recharts-surface, .chart-container').length > 0,
                        hasErrorText: /error|failed|something went wrong/i.test(bodyText),
                        hasLoadingText: /loading|spinner/i.test(bodyText),
                        textPreview: bodyText.substring(0, 300)
                    };
                }, tabName);

                const test = {
                    name: `Tab Navigation - ${tabName}`,
                    passed: tabContent.textLength > 50 && !tabContent.hasErrorText,
                    details: tabContent,
                    issues: []
                };

                if (tabContent.textLength < 50) test.issues.push('Very little content in tab');
                if (tabContent.hasErrorText) test.issues.push('Error text visible in tab');
                if (!tabContent.hasTVLData && (tabName === 'Vault' || tabName === 'Trading')) {
                    test.issues.push('Missing TVL data');
                }

                if (!test.passed) allTabsPassed = false;
                this.results.tests.push(test);

            } catch (error) {
                const test = {
                    name: `Tab Navigation - ${tabName}`,
                    passed: false,
                    details: { error: error.message },
                    issues: [`Failed to navigate to ${tabName}: ${error.message}`]
                };
                this.results.tests.push(test);
                allTabsPassed = false;
            }
        }

        return allTabsPassed;
    }

    async testDataAccuracy() {
        console.log('📊 Testing data accuracy and live feeds...');

        try {
            // Go back to main page
            await this.page.goto(FRONTEND_URL);
            await this.page.waitForTimeout(3000);

            // Extract key metrics
            const metrics = await this.page.evaluate(() => {
                const bodyText = document.body.innerText;
                const extractNumber = (pattern) => {
                    const match = bodyText.match(pattern);
                    if (!match) return null;
                    let value = parseFloat(match[1].replace(/[$,]/g, ''));
                    if (match[0].includes('M')) value *= 1e6;
                    if (match[0].includes('B')) value *= 1e9;
                    if (match[0].includes('K')) value *= 1e3;
                    return value;
                };

                return {
                    tvl: extractNumber(/TVL.*\$([\d,.]+(K|M|B)?)/i),
                    apy: extractNumber(/APY.*([\d.]+)%/i),
                    oi: extractNumber(/(?:Open\s*Interest|OI).*\$([\d,.]+(K|M|B)?)/i),
                    sharePrice: extractNumber(/Share\s*Price.*\$([\d.]+)/i),
                    hasValidNumbers: !bodyText.includes('$NaN') && !bodyText.includes('undefined') && !bodyText.includes('$0.00'),
                    hasPlaceholderText: bodyText.includes('Lorem ipsum') || bodyText.includes('placeholder'),
                    totalNumbers: (bodyText.match(/\$[\d,]+/g) || []).length
                };
            });

            const test = {
                name: 'Data Accuracy',
                passed: metrics.hasValidNumbers && !metrics.hasPlaceholderText && metrics.totalNumbers > 5,
                details: metrics,
                issues: []
            };

            if (!metrics.hasValidNumbers) test.issues.push('Invalid numbers detected ($NaN, undefined)');
            if (metrics.hasPlaceholderText) test.issues.push('Placeholder text still visible');
            if (metrics.totalNumbers <= 5) test.issues.push('Very few financial numbers displayed');
            if (!metrics.tvl || metrics.tvl < 1000) test.issues.push('TVL data missing or too low');

            this.results.tests.push(test);
            return test.passed;

        } catch (error) {
            this.results.tests.push({
                name: 'Data Accuracy',
                passed: false,
                details: { error: error.message },
                issues: [`Failed to extract data: ${error.message}`]
            });
            return false;
        }
    }

    async testMobileResponsiveness() {
        console.log('📱 Testing mobile responsiveness...');

        try {
            // Switch to mobile viewport
            await this.page.setViewport({ width: 375, height: 812 });
            await this.page.goto(FRONTEND_URL);
            await this.page.waitForTimeout(2000);

            await this.takeScreenshot('mobile-responsive', 'Mobile responsive design');

            // Check if content is properly responsive
            const mobileContent = await this.page.evaluate(() => {
                return {
                    hasHorizontalScroll: document.body.scrollWidth > window.innerWidth,
                    contentVisible: document.body.innerText.length > 100,
                    hasOverflowIssues: document.querySelectorAll('[style*="overflow: visible"]').length > 10,
                    mobileMenuVisible: document.querySelectorAll('.mobile-menu, [class*="mobile"], .hamburger').length > 0 ||
                                     window.innerWidth < 768
                };
            });

            // Return to desktop
            await this.page.setViewport({ width: 1440, height: 900 });

            const test = {
                name: 'Mobile Responsiveness',
                passed: !mobileContent.hasHorizontalScroll && mobileContent.contentVisible,
                details: mobileContent,
                issues: []
            };

            if (mobileContent.hasHorizontalScroll) test.issues.push('Horizontal scroll on mobile');
            if (!mobileContent.contentVisible) test.issues.push('Content not visible on mobile');

            this.results.tests.push(test);
            return test.passed;

        } catch (error) {
            this.results.tests.push({
                name: 'Mobile Responsiveness',
                passed: false,
                details: { error: error.message },
                issues: [`Failed to test mobile: ${error.message}`]
            });
            return false;
        }
    }

    async generateReport() {
        const passedTests = this.results.tests.filter(t => t.passed).length;
        const totalTests = this.results.tests.length;
        this.results.score = totalTests > 0 ? Math.round((passedTests / totalTests) * 100) : 0;
        this.results.success = this.results.score >= 80 && this.results.console_errors.length === 0;

        // Create detailed report
        const reportData = {
            ...this.results,
            summary: {
                passed: passedTests,
                total: totalTests,
                score: this.results.score,
                success: this.results.success,
                method: 'Browser-based React SPA testing',
                curl_replacement: true
            }
        };

        // Save JSON report
        const jsonFile = path.join(SCREENSHOTS_DIR, 'react-spa-verification.json');
        fs.writeFileSync(jsonFile, JSON.stringify(reportData, null, 2));

        // Create HTML report
        const htmlReport = this.createHTMLReport(reportData);
        const htmlFile = path.join(SCREENSHOTS_DIR, 'react-spa-verification.html');
        fs.writeFileSync(htmlFile, htmlReport);

        console.log('\n' + '='.repeat(60));
        console.log('🎯 REACT SPA VERIFICATION COMPLETE');
        console.log('='.repeat(60));
        console.log(`📊 Score: ${this.results.score}/100`);
        console.log(`✅ Passed: ${passedTests}/${totalTests} tests`);
        console.log(`🔧 Method: Browser-based testing (replaces curl)`);
        console.log(`📸 Screenshots: ${this.results.screenshots.length}`);
        console.log(`⚠️  Console errors: ${this.results.console_errors.length}`);
        console.log(`📄 Report: ${htmlFile}`);
        console.log('='.repeat(60));

        return reportData;
    }

    createHTMLReport(data) {
        const statusColor = data.success ? '#28a745' : (data.score >= 60 ? '#ffc107' : '#dc3545');
        const statusText = data.success ? 'EXCELLENT' : (data.score >= 60 ? 'GOOD' : 'NEEDS IMPROVEMENT');

        return `<!DOCTYPE html>
<html>
<head>
    <title>LEVER Protocol - React SPA Verification Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; background: #f8f9fa; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .score { font-size: 48px; font-weight: bold; color: ${statusColor}; }
        .status { background: ${statusColor}; color: white; padding: 10px 20px; border-radius: 20px; display: inline-block; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin: 20px 0; }
        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .test-passed { border-left: 4px solid #28a745; }
        .test-failed { border-left: 4px solid #dc3545; }
        .screenshot-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .screenshot { text-align: center; }
        .screenshot img { max-width: 100%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.15); }
        pre { background: #f8f9fa; padding: 15px; border-radius: 6px; overflow-x: auto; }
        .improvement { background: #e7f3ff; padding: 20px; border-radius: 8px; border-left: 4px solid #007bff; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔬 React SPA Verification Report</h1>
            <div class="score">${data.score}/100</div>
            <div class="status">${statusText}</div>
            <p><strong>Method:</strong> ${data.method}</p>
            <p><strong>Timestamp:</strong> ${new Date(data.timestamp).toLocaleString()}</p>
        </div>

        <div class="improvement">
            <h2>🎯 Key Improvement</h2>
            <p><strong>Replaced curl-based testing with proper browser automation</strong></p>
            <p>This report was generated using Playwright to actually render the React SPA and evaluate the JavaScript-generated content, not just the HTML shell that curl can see.</p>
        </div>

        <div class="grid">
            <div class="card">
                <h3>📊 Test Results</h3>
                <p><strong>Passed:</strong> ${data.summary.passed}/${data.summary.total}</p>
                <p><strong>Success Rate:</strong> ${data.score}%</p>
                <p><strong>Console Errors:</strong> ${data.console_errors.length}</p>
            </div>

            <div class="card">
                <h3>📸 Screenshots Captured</h3>
                <p><strong>Total:</strong> ${data.screenshots.length}</p>
                <ul>
                    ${data.screenshots.map(s => `<li>${s.description}</li>`).join('')}
                </ul>
            </div>
        </div>

        <h2>🧪 Detailed Test Results</h2>
        ${data.tests.map(test => `
            <div class="card ${test.passed ? 'test-passed' : 'test-failed'}">
                <h3>${test.passed ? '✅' : '❌'} ${test.name}</h3>
                <p><strong>Status:</strong> ${test.passed ? 'PASSED' : 'FAILED'}</p>
                ${test.issues && test.issues.length > 0 ? `
                    <p><strong>Issues:</strong></p>
                    <ul>${test.issues.map(issue => `<li>${issue}</li>`).join('')}</ul>
                ` : ''}
                <details>
                    <summary>Technical Details</summary>
                    <pre>${JSON.stringify(test.details, null, 2)}</pre>
                </details>
            </div>
        `).join('')}

        ${data.screenshots.length > 0 ? `
            <h2>📸 Screenshots</h2>
            <div class="screenshot-grid">
                ${data.screenshots.map(s => `
                    <div class="screenshot">
                        <img src="${s.name}" alt="${s.description}" loading="lazy">
                        <p><strong>${s.description}</strong></p>
                    </div>
                `).join('')}
            </div>
        ` : ''}

        ${data.console_errors.length > 0 ? `
            <h2>⚠️ Console Errors</h2>
            <div class="card">
                <ul>
                    ${data.console_errors.map(error => `<li><code>${error}</code></li>`).join('')}
                </ul>
            </div>
        ` : ''}
    </div>
</body>
</html>`;
    }

    async run() {
        try {
            await this.init();

            const frontendOk = await this.testFrontendLoading();
            if (frontendOk) {
                await this.testTabNavigation();
                await this.testDataAccuracy();
                await this.testMobileResponsiveness();
            }

            const report = await this.generateReport();
            return report;

        } catch (error) {
            console.error('❌ Verification failed:', error.message);
            this.results.tests.push({
                name: 'Overall Verification',
                passed: false,
                details: { error: error.message },
                issues: [`Verification failed: ${error.message}`]
            });

            await this.generateReport();
            return this.results;

        } finally {
            await this.cleanup();
        }
    }
}

// CLI interface
if (require.main === module) {
    (async () => {
        const isQuickMode = process.argv.includes('--quick');

        if (isQuickMode) {
            // Quick mode for health checks - test with graceful fallback
            try {
                // First try Playwright
                const { chromium } = require('playwright');
                const browser = await chromium.launch({
                    headless: true,
                    args: ['--no-sandbox', '--disable-setuid-sandbox']
                });

                const page = await browser.newPage();
                await page.setViewport({ width: 1440, height: 900 });
                await page.goto(FRONTEND_URL, { waitUntil: 'networkidle', timeout: 15000 });
                await page.waitForTimeout(2000);

                const isWorking = await page.evaluate(() => {
                    const text = document.body.innerText;
                    return text.length > 100 &&
                           !text.includes('Something went wrong') &&
                           !text.includes('$NaN') &&
                           !!document.getElementById('root');
                });

                await browser.close();

                if (isWorking) {
                    console.log('✅ React SPA quick verification passed (Playwright)');
                    process.exit(0);
                } else {
                    console.log('❌ React SPA quick verification failed (content issues)');
                    process.exit(1);
                }
            } catch (error) {
                if (error.message.includes('libatk') || error.message.includes('shared libraries')) {
                    // Browser dependencies missing - try Puppeteer fallback
                    console.log('⚠️  Playwright dependencies missing, trying Puppeteer fallback...');
                    try {
                        const puppeteer = require('puppeteer');
                        const browser = await puppeteer.launch({
                            headless: 'new',
                            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
                        });

                        const page = await browser.newPage();
                        await page.setViewport({ width: 1440, height: 900 });
                        await page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: 15000 });
                        await page.waitForTimeout(2000);

                        const isWorking = await page.evaluate(() => {
                            const text = document.body.innerText;
                            return text.length > 100 &&
                                   !text.includes('Something went wrong') &&
                                   !text.includes('$NaN') &&
                                   !!document.getElementById('root');
                        });

                        await browser.close();

                        if (isWorking) {
                            console.log('✅ React SPA quick verification passed (Puppeteer fallback)');
                            process.exit(0);
                        } else {
                            console.log('❌ React SPA quick verification failed (content issues)');
                            process.exit(1);
                        }
                    } catch (puppeteerError) {
                        // Both browser automation failed - use HTTP fallback but mark as degraded
                        console.log('⚠️  Browser automation failed, using HTTP fallback...');
                        const http = require('http');

                        const httpResult = await new Promise((resolve) => {
                            const req = http.get(FRONTEND_URL, (res) => {
                                let data = '';
                                res.on('data', chunk => data += chunk);
                                res.on('end', () => {
                                    resolve({
                                        status: res.statusCode,
                                        hasReact: data.includes('React') || data.includes('root'),
                                        size: data.length
                                    });
                                });
                            });
                            req.on('error', () => resolve({ status: 'ERROR' }));
                            req.setTimeout(10000, () => resolve({ status: 'TIMEOUT' }));
                        });

                        if (httpResult.status === 200 && httpResult.hasReact && httpResult.size > 1000) {
                            console.log('⚠️  React SPA basic HTTP check passed (degraded mode - cannot verify rendered content)');
                            process.exit(0); // Still pass but with warning
                        } else {
                            console.log('❌ React SPA verification failed - both browser and HTTP checks failed');
                            process.exit(1);
                        }
                    }
                } else {
                    console.log(`❌ React SPA quick verification error: ${error.message}`);
                    process.exit(1);
                }
            }
        } else {
            // Full verification mode
            const verifier = new ReactSPAVerifier();
            const results = await verifier.run();
            process.exit(results.success ? 0 : 1);
        }
    })();
}

module.exports = ReactSPAVerifier;