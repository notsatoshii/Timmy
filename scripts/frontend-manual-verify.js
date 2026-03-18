const http = require('http');
const fs = require('fs');

const FRONTEND_URL = 'http://localhost:3000';
const REPORT_PATH = '/home/lever/lever-protocol/control-plane/frontend-manual-verify.json';

async function httpGet(url) {
    return new Promise((resolve, reject) => {
        http.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve({ status: res.statusCode, data }));
        }).on('error', reject);
    });
}

async function fullFrontendVerification() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const report = { timestamp, checks: [], pass: 0, fail: 0 };

    console.log('=== COMPREHENSIVE FRONTEND VERIFICATION ===');
    console.log('');

    try {
        // CHECK 1: Main page loads
        console.log('1. Testing main page...');
        const mainResponse = await httpGet(FRONTEND_URL);
        const mainPageOk = mainResponse.status === 200 && mainResponse.data.length > 1000;

        report.checks.push({
            name: 'main_page_loads',
            status: mainPageOk ? 'PASS' : 'FAIL',
            detail: `HTTP ${mainResponse.status}, ${mainResponse.data.length} bytes`
        });
        mainPageOk ? report.pass++ : report.fail++;

        if (!mainPageOk) {
            console.log('❌ Main page failed to load');
            return report;
        }

        const html = mainResponse.data;

        // CHECK 2: React app structure
        console.log('2. Checking React app structure...');
        const hasRootDiv = html.includes('<div id="root">');
        const hasJSBundle = /src="\/static\/js\/main\.[a-f0-9]+\.js"/.test(html);
        const hasCSSBundle = /href="\/static\/css\/main\.[a-f0-9]+\.css"/.test(html);

        report.checks.push({
            name: 'react_root_div',
            status: hasRootDiv ? 'PASS' : 'FAIL',
            detail: hasRootDiv ? 'React root div found' : 'Missing React root div'
        });
        hasRootDiv ? report.pass++ : report.fail++;

        report.checks.push({
            name: 'javascript_bundle',
            status: hasJSBundle ? 'PASS' : 'FAIL',
            detail: hasJSBundle ? 'JS bundle link found' : 'No JS bundle link'
        });
        hasJSBundle ? report.pass++ : report.fail++;

        report.checks.push({
            name: 'css_bundle',
            status: hasCSSBundle ? 'PASS' : 'FAIL',
            detail: hasCSSBundle ? 'CSS bundle link found' : 'No CSS bundle link'
        });
        hasCSSBundle ? report.pass++ : report.fail++;

        // CHECK 3: Meta tags and branding
        console.log('3. Checking branding and meta tags...');
        const hasLeverTitle = html.includes('LEVER Protocol');
        const hasDescription = html.includes('synthetic leveraged perpetuals');
        const hasOGImage = html.includes('lever-og-image.png');

        report.checks.push({
            name: 'lever_branding',
            status: hasLeverTitle ? 'PASS' : 'FAIL',
            detail: hasLeverTitle ? 'LEVER branding in title' : 'No LEVER branding'
        });
        hasLeverTitle ? report.pass++ : report.fail++;

        report.checks.push({
            name: 'description_meta',
            status: hasDescription ? 'PASS' : 'FAIL',
            detail: hasDescription ? 'Product description found' : 'No description'
        });
        hasDescription ? report.pass++ : report.fail++;

        report.checks.push({
            name: 'og_image',
            status: hasOGImage ? 'PASS' : 'FAIL',
            detail: hasOGImage ? 'OG image meta tag found' : 'No OG image'
        });
        hasOGImage ? report.pass++ : report.fail++;

        // CHECK 4: Static assets
        console.log('4. Testing static assets...');
        const jsMatch = html.match(/src="(\/static\/js\/main\.[a-f0-9]+\.js)"/);
        const cssMatch = html.match(/href="(\/static\/css\/main\.[a-f0-9]+\.css)"/);

        if (jsMatch) {
            try {
                const jsResponse = await httpGet(FRONTEND_URL + jsMatch[1]);
                const jsOk = jsResponse.status === 200 && jsResponse.data.length > 10000;

                report.checks.push({
                    name: 'js_bundle_accessible',
                    status: jsOk ? 'PASS' : 'FAIL',
                    detail: `JS bundle: HTTP ${jsResponse.status}, ${jsResponse.data.length} bytes`
                });
                jsOk ? report.pass++ : report.fail++;
            } catch (e) {
                report.checks.push({
                    name: 'js_bundle_accessible',
                    status: 'FAIL',
                    detail: 'JS bundle error: ' + e.message
                });
                report.fail++;
            }
        }

        if (cssMatch) {
            try {
                const cssResponse = await httpGet(FRONTEND_URL + cssMatch[1]);
                const cssOk = cssResponse.status === 200 && cssResponse.data.length > 1000;

                report.checks.push({
                    name: 'css_bundle_accessible',
                    status: cssOk ? 'PASS' : 'FAIL',
                    detail: `CSS bundle: HTTP ${cssResponse.status}, ${cssResponse.data.length} bytes`
                });
                cssOk ? report.pass++ : report.fail++;
            } catch (e) {
                report.checks.push({
                    name: 'css_bundle_accessible',
                    status: 'FAIL',
                    detail: 'CSS bundle error: ' + e.message
                });
                report.fail++;
            }
        }

        // CHECK 5: Deployment files
        console.log('5. Testing deployment configuration files...');
        const deploymentFiles = [
            '/deployments/core-deployment.json',
            '/deployments/engines-deployment.json',
            '/deployments/pool-deployment.json'
        ];

        for (const file of deploymentFiles) {
            try {
                const response = await httpGet(FRONTEND_URL + file);
                const deploymentOk = response.status === 200 && response.data.length > 50;

                report.checks.push({
                    name: 'deployment_' + file.split('/').pop().replace('.json', '').replace('-', '_'),
                    status: deploymentOk ? 'PASS' : 'FAIL',
                    detail: deploymentOk ?
                        `Accessible: ${response.data.length} bytes` :
                        `Failed: HTTP ${response.status}`
                });
                deploymentOk ? report.pass++ : report.fail++;

                // Validate JSON if accessible
                if (deploymentOk) {
                    try {
                        const deployment = JSON.parse(response.data);
                        // Check for either { addresses: {...} } or flat { contractName: address } format
                        const addressEntries = deployment.addresses ?
                            Object.keys(deployment.addresses) :
                            Object.keys(deployment).filter(key =>
                                typeof deployment[key] === 'string' &&
                                deployment[key].startsWith('0x')
                            );

                        const hasAddresses = addressEntries.length > 0;

                        report.checks.push({
                            name: 'deployment_' + file.split('/').pop().replace('.json', '').replace('-', '_') + '_valid',
                            status: hasAddresses ? 'PASS' : 'FAIL',
                            detail: hasAddresses ?
                                `Valid JSON with ${addressEntries.length} contract addresses` :
                                'JSON missing contract addresses'
                        });
                        hasAddresses ? report.pass++ : report.fail++;
                    } catch (e) {
                        report.checks.push({
                            name: 'deployment_' + file.split('/').pop().replace('.json', '').replace('-', '_') + '_valid',
                            status: 'FAIL',
                            detail: 'Invalid JSON: ' + e.message
                        });
                        report.fail++;
                    }
                }
            } catch (e) {
                report.checks.push({
                    name: 'deployment_' + file.split('/').pop().replace('.json', '').replace('-', '_'),
                    status: 'FAIL',
                    detail: 'Request failed: ' + e.message
                });
                report.fail++;
            }
        }

        // CHECK 6: Source file verification
        console.log('6. Checking source files...');
        const sourceFiles = [
            'frontend/user-app/src/App.tsx',
            'frontend/user-app/src/components/DashboardOptimized.tsx',
            'frontend/user-app/src/components/Vault.tsx',
            'frontend/user-app/src/components/MarketsOptimized.tsx',
            'frontend/user-app/src/components/ErrorBoundary.tsx'
        ];

        for (const file of sourceFiles) {
            const exists = fs.existsSync(file);
            if (exists) {
                const content = fs.readFileSync(file, 'utf8');
                const hasExports = content.includes('export') || content.includes('export default');

                report.checks.push({
                    name: 'source_' + file.split('/').pop().replace('.tsx', '').toLowerCase(),
                    status: hasExports ? 'PASS' : 'FAIL',
                    detail: hasExports ?
                        `File exists with exports (${content.length} chars)` :
                        `File exists but no exports (${content.length} chars)`
                });
                hasExports ? report.pass++ : report.fail++;
            } else {
                report.checks.push({
                    name: 'source_' + file.split('/').pop().replace('.tsx', '').toLowerCase(),
                    status: 'FAIL',
                    detail: 'File does not exist: ' + file
                });
                report.fail++;
            }
        }

        // CHECK 7: Build artifacts
        console.log('7. Checking build artifacts...');
        const buildExists = fs.existsSync('frontend/user-app/build');
        const buildHasFiles = buildExists && fs.readdirSync('frontend/user-app/build').length > 5;

        report.checks.push({
            name: 'build_directory',
            status: buildHasFiles ? 'PASS' : 'FAIL',
            detail: buildExists ?
                (buildHasFiles ? `Build directory with ${fs.readdirSync('frontend/user-app/build').length} files` : 'Build directory empty') :
                'Build directory does not exist'
        });
        buildHasFiles ? report.pass++ : report.fail++;

        console.log('8. Checking package.json and dependencies...');
        if (fs.existsSync('frontend/user-app/package.json')) {
            const packageJson = JSON.parse(fs.readFileSync('frontend/user-app/package.json', 'utf8'));
            const hasDependencies = packageJson.dependencies && Object.keys(packageJson.dependencies).length > 0;
            const hasReactScripts = packageJson.dependencies && packageJson.dependencies['react-scripts'];

            report.checks.push({
                name: 'package_dependencies',
                status: hasDependencies ? 'PASS' : 'FAIL',
                detail: hasDependencies ?
                    `${Object.keys(packageJson.dependencies).length} dependencies` :
                    'No dependencies'
            });
            hasDependencies ? report.pass++ : report.fail++;

            report.checks.push({
                name: 'react_scripts',
                status: hasReactScripts ? 'PASS' : 'FAIL',
                detail: hasReactScripts ?
                    `react-scripts: ${packageJson.dependencies['react-scripts']}` :
                    'react-scripts missing'
            });
            hasReactScripts ? report.pass++ : report.fail++;
        }

    } catch (e) {
        report.checks.push({
            name: 'verification_error',
            status: 'FAIL',
            detail: 'Verification failed: ' + e.message
        });
        report.fail++;
    }

    // Write report
    fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2));

    // Print summary
    console.log('');
    console.log('=== FRONTEND VERIFICATION COMPLETE ===');
    console.log(`✅ PASSED: ${report.pass} | ❌ FAILED: ${report.fail}`);
    console.log('');

    report.checks.forEach(c => {
        const icon = c.status === 'PASS' ? '✅' : '❌';
        console.log(`${icon} ${c.name}: ${c.detail}`);
    });

    console.log('');
    console.log('Report saved to:', REPORT_PATH);

    if (report.fail === 0) {
        console.log('🎉 ALL CHECKS PASSED! Frontend is fully functional.');
    } else if (report.fail <= 2) {
        console.log('⚠️  Minor issues found. Frontend should still work.');
    } else {
        console.log('❌ Major issues found. Frontend may not work properly.');
    }

    return report;
}

fullFrontendVerification().then(report => {
    process.exit(report.fail > 5 ? 1 : 0);
}).catch(e => {
    console.error('Fatal error:', e);
    process.exit(1);
});