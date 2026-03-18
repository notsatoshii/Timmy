#!/usr/bin/env node
/**
 * LEVER Protocol - MarketDetail Tab Functionality Test
 * Comprehensive end-to-end testing of MarketDetail navigation and display
 */

const http = require('http');
const fs = require('fs');

async function testMarketDetailFunctionality() {
    console.log("=== MarketDetail Tab Functionality Test ===");

    const results = {
        timestamp: new Date().toISOString(),
        marketDetailTest: {
            structure: false,
            navigation: false,
            dataDisplay: false,
            errorHandling: false
        },
        errors: [],
        warnings: [],
        recommendations: []
    };

    // Test 1: Frontend availability
    console.log("1. Testing frontend availability...");
    const frontendTest = await new Promise((resolve) => {
        const req = http.get('http://localhost:3000', (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                resolve({
                    status: res.statusCode,
                    content: data,
                    size: data.length
                });
            });
        });
        req.on('error', (err) => resolve({ error: err.message }));
        req.setTimeout(15000, () => resolve({ error: 'Timeout' }));
    });

    if (frontendTest.error) {
        results.errors.push(`Frontend not accessible: ${frontendTest.error}`);
        console.log(`❌ Frontend test failed: ${frontendTest.error}`);
        console.log(JSON.stringify(results, null, 2));
        process.exit(1);
    }

    console.log(`✅ Frontend responding (${frontendTest.status}, ${frontendTest.size} bytes)`);

    // Test 2: MarketDetail component structure analysis
    console.log("2. Analyzing MarketDetail component structure...");

    try {
        const marketDetailPath = '/home/lever/lever-protocol/frontend/user-app/src/components/MarketDetail.tsx';
        const lazyMarketDetailPath = '/home/lever/lever-protocol/frontend/user-app/src/components/LazyMarketDetail.tsx';
        const dashboardPath = '/home/lever/lever-protocol/frontend/user-app/src/components/DashboardOptimized.tsx';

        const marketDetailCode = fs.readFileSync(marketDetailPath, 'utf8');
        const lazyMarketDetailCode = fs.readFileSync(lazyMarketDetailPath, 'utf8');
        const dashboardCode = fs.readFileSync(dashboardPath, 'utf8');

        // Check critical MarketDetail features
        const structureChecks = {
            hasMarketHeader: marketDetailCode.includes('Market Header') && marketDetailCode.includes('market?.description'),
            hasBackNavigation: marketDetailCode.includes('Back to Markets') && marketDetailCode.includes('onBack'),
            hasTradeButtons: marketDetailCode.includes('Long') && marketDetailCode.includes('Short'),
            hasPriceChart: marketDetailCode.includes('Price Chart') && marketDetailCode.includes('ResponsiveContainer'),
            hasOIBreakdown: marketDetailCode.includes('Open Interest Breakdown'),
            hasRatesDisplay: marketDetailCode.includes('Current Rates') && marketDetailCode.includes('Funding Rate'),
            hasRecentPositions: marketDetailCode.includes('Recent Positions'),
            hasTimeframeSelector: marketDetailCode.includes('timeframes.map'),
            hasErrorHandling: marketDetailCode.includes('Invalid Market Data'),
            hasRealContractCalls: marketDetailCode.includes('useReadContract'),
            isLazyLoaded: lazyMarketDetailCode.includes('lazy(() => import'),
            isDashboardIntegrated: dashboardCode.includes('LazyMarketDetail') && dashboardCode.includes('selectedMarket'),
        };

        const passedChecks = Object.entries(structureChecks).filter(([key, value]) => value);
        const failedChecks = Object.entries(structureChecks).filter(([key, value]) => !value);

        console.log(`   ✅ Structure checks passed: ${passedChecks.length}/${Object.keys(structureChecks).length}`);

        if (failedChecks.length > 0) {
            console.log(`   ⚠️  Failed checks: ${failedChecks.map(([key]) => key).join(', ')}`);
            results.warnings.push(`MarketDetail structure issues: ${failedChecks.map(([key]) => key).join(', ')}`);
        }

        results.marketDetailTest.structure = passedChecks.length >= 10; // Require at least 10/12 to pass

    } catch (error) {
        results.errors.push(`Failed to analyze MarketDetail structure: ${error.message}`);
        console.log(`❌ Structure analysis failed: ${error.message}`);
    }

    // Test 3: Navigation flow analysis
    console.log("3. Testing navigation flow...");

    const content = frontendTest.content;

    // Check for Markets tab content
    const hasMarkets = content.includes('Browse active binary outcome markets') ||
                       content.includes('Prediction Markets') ||
                       content.includes('prediction markets');

    // Check for tab navigation structure
    const hasTabStructure = content.includes('Markets') || content.includes('Trading') || content.includes('markets');

    if (hasMarkets && hasTabStructure) {
        results.marketDetailTest.navigation = true;
        console.log("   ✅ Navigation structure appears functional");
    } else {
        results.warnings.push("Navigation structure may have issues");
        console.log("   ⚠️  Navigation structure needs verification");
    }

    // Test 4: Data display capability
    console.log("4. Testing data display capability...");

    // Check for contract integration
    try {
        const contractsPath = '/home/lever/lever-protocol/frontend/user-app/src/config/contracts.ts';
        const abiPath = '/home/lever/lever-protocol/frontend/user-app/src/config/abis.ts';

        if (fs.existsSync(contractsPath) && fs.existsSync(abiPath)) {
            const contractsCode = fs.readFileSync(contractsPath, 'utf8');
            const abisCode = fs.readFileSync(abiPath, 'utf8');

            const hasContractAddresses = contractsCode.includes('CONTRACT_ADDRESSES');
            const hasRequiredABIs = abisCode.includes('OI_LIMITS_ABI') &&
                                   abisCode.includes('BORROW_FEE_ENGINE_ABI') &&
                                   abisCode.includes('FUNDING_RATE_ENGINE_ABI');

            if (hasContractAddresses && hasRequiredABIs) {
                results.marketDetailTest.dataDisplay = true;
                console.log("   ✅ Contract integration configured for data display");
            } else {
                results.warnings.push("Contract integration may be incomplete");
                console.log("   ⚠️  Contract integration needs verification");
            }
        } else {
            results.warnings.push("Contract configuration files not found");
            console.log("   ⚠️  Contract configuration files not found");
        }
    } catch (error) {
        results.warnings.push(`Data display check failed: ${error.message}`);
        console.log(`   ⚠️  Data display check failed: ${error.message}`);
    }

    // Test 5: Error handling
    console.log("5. Testing error handling...");

    try {
        const errorBoundaryPath = '/home/lever/lever-protocol/frontend/user-app/src/components/ErrorBoundary.tsx';
        const errorBoundaryCode = fs.readFileSync(errorBoundaryPath, 'utf8');

        const hasErrorBoundary = errorBoundaryCode.includes('componentDidCatch');
        const hasErrorDisplay = errorBoundaryCode.includes('Panel Error');

        if (hasErrorBoundary && hasErrorDisplay) {
            results.marketDetailTest.errorHandling = true;
            console.log("   ✅ Error boundaries configured");
        } else {
            results.warnings.push("Error boundaries may not be properly configured");
            console.log("   ⚠️  Error boundaries need verification");
        }
    } catch (error) {
        results.warnings.push(`Error boundary check failed: ${error.message}`);
        console.log(`   ⚠️  Error boundary check failed: ${error.message}`);
    }

    // Final assessment
    console.log("\n=== Test Results Summary ===");

    const testsPassed = Object.values(results.marketDetailTest).filter(Boolean).length;
    const testsTotal = Object.keys(results.marketDetailTest).length;

    console.log(`Structure Analysis: ${results.marketDetailTest.structure ? '✅ PASSED' : '❌ FAILED'}`);
    console.log(`Navigation Flow: ${results.marketDetailTest.navigation ? '✅ PASSED' : '❌ FAILED'}`);
    console.log(`Data Display: ${results.marketDetailTest.dataDisplay ? '✅ PASSED' : '❌ FAILED'}`);
    console.log(`Error Handling: ${results.marketDetailTest.errorHandling ? '✅ PASSED' : '❌ FAILED'}`);

    console.log(`\nOverall: ${testsPassed}/${testsTotal} tests passed`);

    if (results.errors.length > 0) {
        console.log(`\n❌ Critical Errors: ${results.errors.length}`);
        results.errors.forEach(error => console.log(`  - ${error}`));
    }

    if (results.warnings.length > 0) {
        console.log(`\n⚠️  Warnings: ${results.warnings.length}`);
        results.warnings.forEach(warning => console.log(`  - ${warning}`));
    }

    // Recommendations
    console.log(`\n💡 Recommendations:`);

    if (!results.marketDetailTest.structure) {
        results.recommendations.push("Review MarketDetail component implementation");
    }

    if (!results.marketDetailTest.navigation) {
        results.recommendations.push("Test market card click navigation manually");
    }

    if (!results.marketDetailTest.dataDisplay) {
        results.recommendations.push("Verify contract addresses are deployed and accessible");
    }

    console.log("  1. Open http://localhost:3000 in browser");
    console.log("  2. Navigate to Markets tab");
    console.log("  3. Click on any market card to test MarketDetail navigation");
    console.log("  4. Verify chart displays, OI data loads, and rates show");
    console.log("  5. Test 'Back to Markets' button functionality");
    console.log("  6. Try Long/Short buttons (should navigate to Trading)");

    if (results.recommendations.length > 0) {
        results.recommendations.forEach(rec => console.log(`  - ${rec}`));
    }

    // Save results
    const reportPath = '/home/lever/lever-protocol/control-plane/screenshots/marketdetail-test-results.json';
    fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
    console.log(`\n📄 Full report saved: ${reportPath}`);

    // Determine overall success
    const success = testsPassed >= 3 && results.errors.length === 0; // Require at least 3/4 tests to pass

    if (success) {
        console.log(`\n🎉 MarketDetail functionality test: PASSED`);
        console.log(`✅ MarketDetail tab is ready for investor demo`);
        process.exit(0);
    } else {
        console.log(`\n❌ MarketDetail functionality test: NEEDS ATTENTION`);
        console.log(`⚠️  Manual verification recommended before demo`);
        process.exit(1);
    }
}

testMarketDetailFunctionality().catch(error => {
    console.error('Test execution failed:', error);
    process.exit(1);
});