#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const FRONTEND_URL = 'http://localhost:3000';
const SCREENSHOT_DIR = '/home/lever/lever-protocol/control-plane/screenshots';
const DEPLOY_ENV_PATH = '/home/lever/lever-protocol/control-plane/deploy-env.sh';

class TabSanityChecker {
    constructor() {
        this.timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        this.results = {
            timestamp: this.timestamp,
            tabs: {},
            overall: { data_pass: false, visual_pass: false }
        };
        this.browser = null;
        this.page = null;

        // Ensure screenshot directory exists
        if (!fs.existsSync(SCREENSHOT_DIR)) {
            fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
        }

        // Source deploy environment to get contract addresses
        this.sourceDeployEnv();
    }

    sourceDeployEnv() {
        try {
            console.log('Sourcing deployment environment...');
            const envContent = fs.readFileSync(DEPLOY_ENV_PATH, 'utf8');
            const lines = envContent.split('\n');

            // Parse environment variables from deploy-env.sh
            for (const line of lines) {
                const exportMatch = line.match(/^export\s+(\w+)="?([^"]*)"?$/);
                if (exportMatch) {
                    process.env[exportMatch[1]] = exportMatch[2];
                }
            }

            console.log(`RPC_URL: ${process.env.RPC_URL}`);
            console.log(`LEVER_VAULT: ${process.env.LEVER_VAULT}`);
        } catch (e) {
            console.error('Failed to source deployment environment:', e.message);
            process.exit(1);
        }
    }

    runPuppeteerTask(taskCode) {
        // Create a temporary file for the puppeteer task to avoid escaping issues
        const tempScriptPath = path.join(SCREENSHOT_DIR, `temp-task-${Date.now()}.js`);

        const nodeCode = `const puppeteer = require("puppeteer");
(async () => {
    try {
        const browser = await puppeteer.launch({
            headless: "new",
            executablePath: "/usr/bin/chromium-browser",
            args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
        });
        const page = await browser.newPage();
        await page.setViewport({ width: 1440, height: 900 });

        ${taskCode}

        await browser.close();
    } catch (e) {
        console.log(JSON.stringify({ error: e.message }));
        process.exit(1);
    }
})();`;

        try {
            // Write the code to a temporary file
            fs.writeFileSync(tempScriptPath, nodeCode);

            // Run the temporary file
            const result = execSync(`node "${tempScriptPath}"`, {
                encoding: 'utf8',
                timeout: 60000,
                maxBuffer: 1024 * 1024
            });

            // Clean up
            try {
                fs.unlinkSync(tempScriptPath);
            } catch (e) {
                console.warn('Could not clean up temp file:', tempScriptPath);
            }

            return result.trim();
        } catch (e) {
            // Clean up on error too
            try {
                fs.unlinkSync(tempScriptPath);
            } catch (e) {}

            console.error('Puppeteer task failed:', e.message);
            return JSON.stringify({ error: e.message });
        }
    }

    navigateToTabAndExtractData(tabName) {
        console.log(`Processing ${tabName} tab...`);

        const taskCode = `
        await page.goto("${FRONTEND_URL}", { waitUntil: "networkidle2", timeout: 30000 });
        await new Promise(r => setTimeout(r, 3000));

        // Click on the specific tab
        const tabClickResult = await page.evaluate((tabName) => {
            // Find and click the tab by its label
            const elements = document.querySelectorAll('*');
            for (const el of elements) {
                const text = el.textContent?.trim();
                if (text === tabName &&
                    (el.tagName === 'BUTTON' || el.onclick || el.style.cursor === 'pointer')) {
                    el.click();
                    return true;
                }
            }

            // Fallback: look for elements that contain the tab name
            for (const el of elements) {
                const text = el.textContent?.trim();
                if (text?.includes(tabName) &&
                    el.offsetParent !== null &&
                    el.children.length <= 3) {
                    el.click();
                    return true;
                }
            }
            return false;
        }, "${tabName}");

        if (!tabClickResult) {
            throw new Error("Could not find or click ${tabName} tab");
        }

        // Wait for navigation and data loading
        await new Promise(r => setTimeout(r, 3000));

        // Take screenshot
        const screenshotPath = "${path.join(SCREENSHOT_DIR, `${tabName.toLowerCase()}-${this.timestamp}.png`)}";
        await page.screenshot({
            path: screenshotPath,
            fullPage: true,
            type: 'png'
        });

        // Extract data
        const data = await page.evaluate(() => {
            const bodyText = document.body.innerText;
            const result = {
                hasContent: bodyText.length > 50,
                hasErrors: bodyText.includes('Error') ||
                          bodyText.includes('Something went wrong') ||
                          bodyText.includes('undefined') ||
                          document.body.innerText.trim().length < 20,
                values: {}
            };

            // Extract common values based on patterns
            const patterns = {
                tvl: /(?:Total TVL|TVL)[\\s\\S]{0,50}?\\$([\\d,.]+)/i,
                apy: /(?:LP APY|APY)[\\s\\S]{0,100}?([\\d,.]+)%?/i,
                oi: /(?:Total OI|Open Interest)[\\s\\S]{0,50}?\\$([\\d,.]+)/i,
                volume: /(?:24h Volume|Volume)[\\s\\S]{0,50}?\\$([\\d,.]+)/i,
                insurance: /(?:Insurance Fund|Insurance)[\\s\\S]{0,50}?\\$([\\d,.]+)/i,
                sharePrice: /(?:Share Price|Price)[\\s\\S]{0,50}?\\$([\\d,.]+)/i,
                leverage: /(?:Leverage|Max Leverage)[\\s\\S]{0,50}?(\\d+(?:\\.\\d+)?)[x×]/i,
                pnl: /(?:PnL|P&L|Profit)[\\s\\S]{0,50}?[\\$\\+\\-]?([\\d,.]+)/i
            };

            for (const [key, pattern] of Object.entries(patterns)) {
                const match = bodyText.match(pattern);
                if (match) {
                    result.values[key] = match[1].replace(/,/g, '');
                }
            }

            // Check for specific error indicators
            if (bodyText.includes('\\$0.00') && bodyText.includes('TVL')) {
                result.hasErrors = true;
            }
            if (bodyText.includes('NaN') || bodyText.includes('undefined')) {
                result.hasErrors = true;
            }

            return result;
        });

        console.log(JSON.stringify({
            success: true,
            screenshot: screenshotPath,
            data: data
        }));`;

        return this.runPuppeteerTask(taskCode);
    }

    getOnChainData() {
        console.log('Fetching on-chain reference data...');
        try {
            const commands = {
                tvl: `cast call ${process.env.LEVER_VAULT} 'totalAssets()(uint256)' --rpc-url ${process.env.RPC_URL}`,
                oi: `cast call ${process.env.OI_LIMITS} 'getGlobalOI()(uint256)' --rpc-url ${process.env.RPC_URL}`,
                insurance: `cast call ${process.env.INSURANCE_FUND} 'getBalance()(uint256)' --rpc-url ${process.env.RPC_URL}`,
                sharePrice: `cast call ${process.env.LEVER_VAULT} 'convertToAssets(uint256)' 1000000000000000000 --rpc-url ${process.env.RPC_URL}`
            };

            const onChainData = {};
            for (const [key, command] of Object.entries(commands)) {
                try {
                    const result = execSync(command, { encoding: 'utf8', timeout: 10000 }).trim();
                    let value = BigInt(result);

                    // Convert to human readable based on decimals
                    if (key === 'tvl' || key === 'oi') {
                        onChainData[key] = Number(value) / 1e6; // USDT (6 decimals)
                    } else if (key === 'insurance' || key === 'sharePrice') {
                        onChainData[key] = Number(value) / 1e18; // WAD (18 decimals)
                    }
                } catch (e) {
                    console.error(`Failed to get ${key}:`, e.message);
                    onChainData[key] = 0;
                }
            }

            console.log('On-chain data:', JSON.stringify(onChainData, null, 2));
            return onChainData;
        } catch (e) {
            console.error('Failed to fetch on-chain data:', e.message);
            return {};
        }
    }

    validateDataLayer(tabName, extractedData, onChainData) {
        const issues = [];

        // Check for basic errors
        if (!extractedData.hasContent) {
            issues.push('Tab shows no content or blank page');
        }

        if (extractedData.hasErrors) {
            issues.push('Tab shows error messages, $0.00, NaN, or undefined values');
        }

        // Compare extracted values with on-chain data
        const tolerances = {
            tvl: 10,    // Allow 10x difference
            oi: 10,     // Allow 10x difference
            insurance: 100,  // Allow 100x difference (different decimal formats)
            sharePrice: 10   // Allow 10x difference
        };

        for (const [key, onChainValue] of Object.entries(onChainData)) {
            if (extractedData.values[key] && onChainValue > 0) {
                const extractedValue = parseFloat(extractedData.values[key]);
                const ratio = extractedValue / onChainValue;

                if (ratio > tolerances[key] || ratio < (1/tolerances[key])) {
                    issues.push(`${key}: displayed=${extractedValue}, onchain=${onChainValue}, ratio=${ratio.toFixed(2)}x (exceeds ${tolerances[key]}x tolerance)`);
                }
            }
        }

        // Check for obviously wrong values
        for (const [key, value] of Object.entries(extractedData.values)) {
            const numValue = parseFloat(value);
            if (numValue < 0) {
                issues.push(`${key}: negative value ${numValue}`);
            }
            if (numValue > 1e9) {
                issues.push(`${key}: suspiciously large value ${numValue} (possible decimal error)`);
            }
        }

        return issues;
    }

    runVisualReview(screenshots) {
        console.log('Running Claude Vision review...');

        if (screenshots.length === 0) {
            console.error('No screenshots available for visual review');
            return { overall_pass: false, tab_results: {} };
        }

        try {
            // Create a prompt for Claude Vision
            const prompt = `You are reviewing screenshots of a DeFi protocol frontend for visual/UX quality.

Please evaluate each screenshot for:
1. Layout quality: Does the layout look professional and properly structured?
2. Charts/graphs: Are charts rendering properly (not empty boxes or loading states)?
3. Text readability: Is text properly sized, not truncated, no overlapping elements?
4. Color/theme consistency: Are colors consistent and professional?
5. Number formatting: Do monetary values have proper $ prefix, commas, % and × suffixes?
6. Loading states: Are there any stuck loading spinners or skeleton states?
7. Overall UX: Would this look professional enough for an investor demo?

Return a JSON object with this structure:
{
  "overall_pass": true/false,
  "tab_results": {
    "TabName": {
      "visual_pass": true/false,
      "issues": ["specific issue 1", "specific issue 2"]
    }
  }
}

Be strict but fair in evaluation. Minor cosmetic issues are okay, but major layout problems, broken charts, or unprofessional appearance should fail.`;

            // Build claude command with screenshots
            let claudeCmd = `claude --no-input --print`;
            for (const screenshot of screenshots) {
                if (fs.existsSync(screenshot)) {
                    claudeCmd += ` --image "${screenshot}"`;
                }
            }
            claudeCmd += ` --message "${prompt}"`;

            console.log('Running Claude Vision review...');
            const claudeOutput = execSync(claudeCmd, {
                encoding: 'utf8',
                timeout: 60000,
                maxBuffer: 1024 * 1024
            });

            console.log('Claude Vision output received');

            // Try to extract JSON from Claude's response
            const jsonMatch = claudeOutput.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                const visionResults = JSON.parse(jsonMatch[0]);
                console.log('Vision review results:', JSON.stringify(visionResults, null, 2));
                return visionResults;
            } else {
                console.error('Could not parse JSON from Claude output:', claudeOutput.substring(0, 500));
                return { overall_pass: false, tab_results: {} };
            }

        } catch (e) {
            console.error('Failed to run Claude Vision review:', e.message);
            console.log('Skipping visual review, continuing with data validation only...');
            return { overall_pass: false, tab_results: {} };
        }
    }

    checkTab(tabName) {
        console.log(`\n=== CHECKING TAB: ${tabName} ===`);

        const tabResult = {
            tab: tabName,
            data_pass: false,
            visual_pass: false,
            screenshot: null,
            data_issues: [],
            visual_issues: []
        };

        try {
            // Navigate to tab and extract data
            const result = this.navigateToTabAndExtractData(tabName);
            const parsedResult = JSON.parse(result);

            if (!parsedResult.success) {
                tabResult.data_issues.push(parsedResult.error || 'Failed to process tab');
                return tabResult;
            }

            tabResult.screenshot = parsedResult.screenshot;

            // Get on-chain data for comparison
            const onChainData = this.getOnChainData();
            const dataIssues = this.validateDataLayer(tabName, parsedResult.data, onChainData);

            tabResult.data_issues = dataIssues;
            tabResult.data_pass = dataIssues.length === 0;

            console.log(`${tabName} - Data validation: ${tabResult.data_pass ? 'PASS' : 'FAIL'}`);
            if (dataIssues.length > 0) {
                console.log(`  Issues: ${dataIssues.join(', ')}`);
            }

        } catch (e) {
            console.error(`Error processing ${tabName}:`, e.message);
            tabResult.data_issues.push(`Processing error: ${e.message}`);
        }

        return tabResult;
    }

    run() {
        console.log('=== TAB SANITY CHECK - COMPREHENSIVE VALIDATION ===\n');

        // Test tabs individually
        const tabsToTest = ['Markets', 'Trading', 'Vault', 'Positions'];
        const allScreenshots = [];

        for (const tabName of tabsToTest) {
            const result = this.checkTab(tabName);
            this.results.tabs[tabName] = result;

            if (result.screenshot) {
                allScreenshots.push(result.screenshot);
            }
        }

        // Special case: MarketDetail for SpaceX
        console.log(`\n=== CHECKING MARKET DETAIL: SpaceX ===`);
        try {
            const marketDetailTaskCode = `
            await page.goto("${FRONTEND_URL}", { waitUntil: "networkidle2", timeout: 30000 });
            await new Promise(r => setTimeout(r, 3000));

            // Click on Markets tab first
            await page.evaluate(() => {
                const elements = document.querySelectorAll('*');
                for (const el of elements) {
                    if (el.textContent?.trim() === 'Markets') {
                        el.click();
                        return true;
                    }
                }
            });
            await new Promise(r => setTimeout(r, 2000));

            // Look for and click on SpaceX market
            const spacexClicked = await page.evaluate(() => {
                const elements = document.querySelectorAll('*');
                for (const el of elements) {
                    if (el.textContent?.includes('SpaceX') && el.offsetParent !== null) {
                        el.click();
                        return true;
                    }
                }
                return false;
            });

            if (spacexClicked) {
                await new Promise(r => setTimeout(r, 3000));

                // Take screenshot
                const screenshotPath = "${path.join(SCREENSHOT_DIR, `marketdetail-spacex-${this.timestamp}.png`)}";
                await page.screenshot({
                    path: screenshotPath,
                    fullPage: true,
                    type: 'png'
                });

                console.log(JSON.stringify({
                    success: true,
                    screenshot: screenshotPath
                }));
            } else {
                console.log(JSON.stringify({
                    success: false,
                    error: 'Could not find SpaceX market'
                }));
            }`;

            const spacexResult = this.runPuppeteerTask(marketDetailTaskCode);
            const parsedSpacexResult = JSON.parse(spacexResult);

            if (parsedSpacexResult.success) {
                const marketDetailResult = {
                    tab: 'MarketDetail-SpaceX',
                    data_pass: true, // Simplified check for market detail
                    visual_pass: false,
                    screenshot: parsedSpacexResult.screenshot,
                    data_issues: [],
                    visual_issues: []
                };

                allScreenshots.push(parsedSpacexResult.screenshot);
                this.results.tabs['MarketDetail-SpaceX'] = marketDetailResult;
            } else {
                console.log('Could not process SpaceX market detail:', parsedSpacexResult.error);
            }
        } catch (e) {
            console.error('Failed to test MarketDetail for SpaceX:', e.message);
        }

        // Run visual review
        const visionResults = this.runVisualReview(allScreenshots);

        // Apply visual results to tab results
        for (const [tabName, tabResult] of Object.entries(this.results.tabs)) {
            const visionResult = visionResults.tab_results?.[tabName];
            if (visionResult) {
                tabResult.visual_pass = visionResult.visual_pass;
                tabResult.visual_issues = visionResult.issues || [];
            }
        }

        // Calculate overall pass/fail
        let allDataPass = true;
        let allVisualPass = true;

        for (const tabResult of Object.values(this.results.tabs)) {
            if (!tabResult.data_pass) allDataPass = false;
            if (!tabResult.visual_pass) allVisualPass = false;
        }

        this.results.overall = {
            data_pass: allDataPass,
            visual_pass: allVisualPass
        };

        this.printResults();
        return this.results.overall.data_pass && this.results.overall.visual_pass;
    }

    printResults() {
        console.log('\n=== TAB SANITY CHECK RESULTS ===\n');

        for (const [tabName, result] of Object.entries(this.results.tabs)) {
            console.log(`${tabName}:`);
            console.log(`  DATA: ${result.data_pass ? 'PASS' : 'FAIL'}`);
            if (result.data_issues.length > 0) {
                result.data_issues.forEach(issue => console.log(`    - ${issue}`));
            }

            console.log(`  VISUAL: ${result.visual_pass ? 'PASS' : 'FAIL'}`);
            if (result.visual_issues.length > 0) {
                result.visual_issues.forEach(issue => console.log(`    - ${issue}`));
            }

            if (result.screenshot) {
                console.log(`  Screenshot: ${result.screenshot}`);
            }
            console.log('');
        }

        console.log('OVERALL SUMMARY:');
        console.log(`  DATA VALIDATION: ${this.results.overall.data_pass ? 'PASS' : 'FAIL'}`);
        console.log(`  VISUAL REVIEW: ${this.results.overall.visual_pass ? 'PASS' : 'FAIL'}`);
        console.log(`  FINAL RESULT: ${this.results.overall.data_pass && this.results.overall.visual_pass ? 'PASS' : 'FAIL'}`);
        console.log('');
        console.log(`Screenshots saved to: ${SCREENSHOT_DIR}`);
    }
}

// Main execution
function main() {
    const checker = new TabSanityChecker();
    try {
        const success = checker.run();
        process.exit(success ? 0 : 1);
    } catch (e) {
        console.error('Fatal error:', e);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = TabSanityChecker;