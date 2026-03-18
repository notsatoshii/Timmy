const http = require('http');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'http://localhost:3000';
const REPORT_PATH = '/home/lever/lever-protocol/control-plane/frontend-check.json';

async function checkFrontend() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const report = { timestamp, checks: [], pass: 0, fail: 0 };

    console.log('Frontend verification (fallback mode - no browser)...');

    try {
        // CHECK 1: HTTP Response
        const htmlContent = await new Promise((resolve, reject) => {
            http.get(FRONTEND_URL, (res) => {
                if (res.statusCode !== 200) {
                    reject(new Error(`HTTP ${res.statusCode}`));
                    return;
                }
                let data = '';
                res.on('data', (chunk) => data += chunk);
                res.on('end', () => resolve(data));
            }).on('error', reject);
        });

        report.checks.push({
            name: 'http_response',
            status: 'PASS',
            detail: 'HTTP 200 OK, ' + htmlContent.length + ' bytes'
        });
        report.pass++;

        // CHECK 2: HTML contains React app structure
        const hasReactRoot = htmlContent.includes('<div id="root">');
        report.checks.push({
            name: 'react_structure',
            status: hasReactRoot ? 'PASS' : 'FAIL',
            detail: hasReactRoot ? 'React root div found' : 'Missing React root div'
        });
        hasReactRoot ? report.pass++ : report.fail++;

        // CHECK 3: LEVER branding in meta tags
        const hasLeverBranding = htmlContent.includes('LEVER Protocol');
        report.checks.push({
            name: 'lever_branding',
            status: hasLeverBranding ? 'PASS' : 'FAIL',
            detail: hasLeverBranding ? 'LEVER branding in meta tags' : 'No LEVER branding found'
        });
        hasLeverBranding ? report.pass++ : report.fail++;

        // CHECK 4: JavaScript bundle
        const jsMatch = htmlContent.match(/src="\/static\/js\/main\.[a-f0-9]+\.js"/);
        const hasJSBundle = !!jsMatch;
        report.checks.push({
            name: 'js_bundle',
            status: hasJSBundle ? 'PASS' : 'FAIL',
            detail: hasJSBundle ? 'JS bundle: ' + jsMatch[0] : 'No JS bundle found'
        });
        hasJSBundle ? report.pass++ : report.fail++;

        // CHECK 5: CSS bundle
        const cssMatch = htmlContent.match(/href="\/static\/css\/main\.[a-f0-9]+\.css"/);
        const hasCSS = !!cssMatch;
        report.checks.push({
            name: 'css_bundle',
            status: hasCSS ? 'PASS' : 'FAIL',
            detail: hasCSS ? 'CSS bundle: ' + cssMatch[0] : 'No CSS bundle found'
        });
        hasCSS ? report.pass++ : report.fail++;

        // CHECK 6: Deployment files accessible
        const deploymentFiles = [
            '/deployments/core-deployment.json',
            '/deployments/engines-deployment.json',
            '/deployments/pool-deployment.json'
        ];

        for (const file of deploymentFiles) {
            try {
                await new Promise((resolve, reject) => {
                    http.get(FRONTEND_URL + file, (res) => {
                        if (res.statusCode === 200) {
                            resolve();
                        } else {
                            reject(new Error(`HTTP ${res.statusCode}`));
                        }
                    }).on('error', reject);
                });

                report.checks.push({
                    name: 'deployment_' + path.basename(file, '.json').replace('-', '_'),
                    status: 'PASS',
                    detail: 'File accessible: ' + file
                });
                report.pass++;
            } catch (e) {
                report.checks.push({
                    name: 'deployment_' + path.basename(file, '.json').replace('-', '_'),
                    status: 'FAIL',
                    detail: 'Not accessible: ' + file + ' (' + e.message + ')'
                });
                report.fail++;
            }
        }

        // CHECK 7: React app source files exist
        const sourceFiles = [
            'frontend/user-app/src/App.tsx',
            'frontend/user-app/src/components/Dashboard.tsx',
            'frontend/user-app/src/components/Vault.tsx',
            'frontend/user-app/src/components/MarketsOptimized.tsx'
        ];

        for (const file of sourceFiles) {
            const exists = fs.existsSync(file);
            report.checks.push({
                name: 'source_' + path.basename(file, '.tsx').toLowerCase(),
                status: exists ? 'PASS' : 'FAIL',
                detail: exists ? 'File exists: ' + file : 'Missing: ' + file
            });
            exists ? report.pass++ : report.fail++;
        }

    } catch (e) {
        report.checks.push({
            name: 'frontend_access',
            status: 'FAIL',
            detail: 'Cannot access frontend: ' + e.message
        });
        report.fail++;
    }

    // Write report
    fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2));

    // Print summary
    console.log('');
    console.log('=== FRONTEND CHECK: ' + report.pass + ' passed, ' + report.fail + ' failed ===');
    report.checks.forEach(c => {
        console.log('  ' + c.status + ': ' + c.name + ' — ' + c.detail);
    });
    console.log('');
    console.log('Report: ' + REPORT_PATH);
    console.log('');

    if (report.fail > 0) {
        console.log('Issues found. Frontend may not be working correctly.');
        console.log('Note: This is a basic check. For full UI verification, fix browser issues and run visual-verify.js');
    } else {
        console.log('Basic frontend checks PASSED. Frontend structure looks good.');
        console.log('Note: This only tests basic accessibility. For UI verification, run visual-verify.js');
    }

    process.exit(report.fail > 0 ? 1 : 0);
}

checkFrontend().catch(e => {
    console.error('Fatal:', e);
    process.exit(1);
});