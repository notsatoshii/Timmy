#!/usr/bin/env node

const { basicUITest } = require('./basic-ui-test.js');
const fs = require('fs');
const path = require('path');

const DIR = '/home/lever/lever-protocol/control-plane/screenshots';

async function runFullVerification() {
    console.log('🔍 LEVER Frontend Verification');
    console.log('================================');

    const results = {
        timestamp: new Date().toISOString(),
        screenshot_test: null,
        basic_ui_test: null,
        overall_status: 'UNKNOWN',
        recommendations: []
    };

    // Step 1: Try screenshot automation
    console.log('\n🖥️  STEP 1: Screenshot Automation');
    console.log('==================================');

    try {
        const { execSync } = require('child_process');
        execSync('node scripts/take-screenshots.js', { stdio: 'inherit', timeout: 60000 });

        // Check if screenshots were actually created
        const reviewFile = path.join(DIR, 'latest-review.json');
        if (fs.existsSync(reviewFile)) {
            const review = JSON.parse(fs.readFileSync(reviewFile, 'utf8'));
            results.screenshot_test = review;

            if (review.success && review.screenshots && review.screenshots.length > 0) {
                console.log('✅ Screenshot automation succeeded');
                results.overall_status = 'PASS';
            } else if (review.fallback_used && review.frontend_check && !review.frontend_check.includes('unreachable')) {
                console.log('⚠️  Screenshots failed but frontend is responding');
                results.overall_status = 'WARN';
                results.recommendations.push('Screenshots unavailable - manual verification recommended');
            } else {
                console.log('❌ Screenshot automation failed');
                results.overall_status = 'FAIL';
            }
        }
    } catch (error) {
        console.log('❌ Screenshot script failed');
        results.screenshot_test = { error: error.message };
        results.overall_status = 'FAIL';
    }

    // Step 2: Basic UI validation
    console.log('\n🧪 STEP 2: Basic UI Validation');
    console.log('===============================');

    try {
        const uiTestPassed = await basicUITest();

        // Read the detailed results
        const uiResultsFile = path.join(DIR, 'basic-ui-test.json');
        if (fs.existsSync(uiResultsFile)) {
            results.basic_ui_test = JSON.parse(fs.readFileSync(uiResultsFile, 'utf8'));
        }

        if (uiTestPassed) {
            console.log('✅ Basic UI validation passed');
            // If screenshot failed but UI test passed, mark as WARN instead of FAIL
            if (results.overall_status === 'FAIL') {
                results.overall_status = 'WARN';
                results.recommendations.push('UI is functional but visual verification needed');
            }
        } else {
            console.log('❌ Basic UI validation failed');
            results.overall_status = 'FAIL';
            results.recommendations.push('Frontend has issues - check logs');
        }

    } catch (error) {
        console.log('❌ Basic UI test crashed');
        results.basic_ui_test = { error: error.message };
        results.overall_status = 'FAIL';
        results.recommendations.push('UI testing failed - manual check required');
    }

    // Step 3: Final assessment and recommendations
    console.log('\n📋 STEP 3: Final Assessment');
    console.log('============================');

    if (results.overall_status === 'PASS') {
        console.log('🎉 All UI verification checks passed!');
    } else if (results.overall_status === 'WARN') {
        console.log('⚠️  UI appears functional but with limitations:');
        results.recommendations.forEach(rec => console.log(`   • ${rec}`));
    } else {
        console.log('💥 UI verification failed:');
        results.recommendations.forEach(rec => console.log(`   • ${rec}`));
    }

    // Manual verification instructions
    if (results.overall_status !== 'PASS') {
        console.log('\n🔧 Manual Verification Steps:');
        console.log('1. Open http://localhost:3000 in your browser');
        console.log('2. Check that Markets, Trading, Vault, and Positions tabs load');
        console.log('3. Verify no blank screens or error messages');
        console.log('4. Check browser developer console for errors');
    }

    // Save comprehensive report
    fs.writeFileSync(path.join(DIR, 'verification-report.json'), JSON.stringify(results, null, 2));

    console.log(`\n📄 Full report saved to: ${path.join(DIR, 'verification-report.json')}`);

    return results.overall_status === 'PASS';
}

if (require.main === module) {
    runFullVerification().then(success => {
        process.exit(success ? 0 : 1);
    }).catch(error => {
        console.error('💥 Verification crashed:', error);
        process.exit(1);
    });
}

module.exports = { runFullVerification };