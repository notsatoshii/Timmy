#!/usr/bin/env node

const http = require('http');
const https = require('https');

const FRONTEND_URL = 'http://localhost:3000';
const TIMEOUT = 10000;

async function httpRequest(url, timeout = TIMEOUT) {
    return new Promise((resolve, reject) => {
        const client = url.startsWith('https') ? https : http;
        const req = client.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve({
                statusCode: res.statusCode,
                headers: res.headers,
                body: data
            }));
        });

        req.on('error', reject);
        req.setTimeout(timeout, () => {
            req.destroy();
            reject(new Error('Request timeout'));
        });
    });
}

async function basicUITest() {
    console.log('🧪 Basic UI Load Test');
    console.log('===================');

    const results = {
        timestamp: new Date().toISOString(),
        tests: [],
        overall_status: 'PASS',
        summary: ''
    };

    // Test 1: Frontend responds
    try {
        console.log('1️⃣  Testing frontend response...');
        const response = await httpRequest(FRONTEND_URL);

        if (response.statusCode === 200) {
            console.log('   ✅ Frontend responding (status 200)');
            results.tests.push({
                name: 'Frontend Response',
                status: 'PASS',
                details: `Status: ${response.statusCode}`
            });
        } else {
            console.log(`   ❌ Frontend returned status ${response.statusCode}`);
            results.tests.push({
                name: 'Frontend Response',
                status: 'FAIL',
                details: `Status: ${response.statusCode}`
            });
            results.overall_status = 'FAIL';
        }

        // Test 2: Check HTML content basics
        console.log('2️⃣  Testing HTML content...');
        const body = response.body;

        const checks = [
            { name: 'React Root', pattern: /<div[^>]*id=["']root["']/, required: true },
            { name: 'Title Tag', pattern: /<title[^>]*>/, required: true },
            { name: 'JavaScript Bundle', pattern: /<script[^>]*src/, required: true },
            { name: 'CSS Styles', pattern: /<link[^>]*stylesheet|<style/, required: false },
            { name: 'Meta Viewport', pattern: /<meta[^>]*viewport/, required: false }
        ];

        for (const check of checks) {
            if (check.pattern.test(body)) {
                console.log(`   ✅ ${check.name} found`);
                results.tests.push({
                    name: `HTML Content - ${check.name}`,
                    status: 'PASS',
                    details: 'Pattern found in HTML'
                });
            } else if (check.required) {
                console.log(`   ❌ ${check.name} missing (required)`);
                results.tests.push({
                    name: `HTML Content - ${check.name}`,
                    status: 'FAIL',
                    details: 'Required pattern not found'
                });
                results.overall_status = 'FAIL';
            } else {
                console.log(`   ⚠️  ${check.name} missing (optional)`);
                results.tests.push({
                    name: `HTML Content - ${check.name}`,
                    status: 'WARN',
                    details: 'Optional pattern not found'
                });
            }
        }

        // Test 3: Check for obvious error indicators
        console.log('3️⃣  Testing for error indicators...');
        const errorPatterns = [
            'Cannot GET /',
            'Error: ',
            'Application error',
            'Something went wrong',
            'Failed to fetch'
        ];

        let errorsFound = 0;
        for (const pattern of errorPatterns) {
            if (body.includes(pattern)) {
                console.log(`   ❌ Found error indicator: "${pattern}"`);
                results.tests.push({
                    name: 'Error Indicators',
                    status: 'FAIL',
                    details: `Found: "${pattern}"`
                });
                results.overall_status = 'FAIL';
                errorsFound++;
            }
        }

        if (errorsFound === 0) {
            console.log('   ✅ No obvious error indicators found');
            results.tests.push({
                name: 'Error Indicators',
                status: 'PASS',
                details: 'No error patterns detected'
            });
        }

    } catch (error) {
        console.log(`   ❌ Frontend test failed: ${error.message}`);
        results.tests.push({
            name: 'Frontend Response',
            status: 'FAIL',
            details: error.message
        });
        results.overall_status = 'FAIL';
    }

    // Test 4: Check if it looks like a React app
    try {
        console.log('4️⃣  Testing React app indicators...');
        const response = await httpRequest(FRONTEND_URL);
        const body = response.body;

        const reactIndicators = [
            'react',
            'React',
            'ReactDOM',
            '__webpack',
            'app.js',
            'main.js',
            'bundle.js'
        ];

        let reactSignsFound = 0;
        for (const indicator of reactIndicators) {
            if (body.includes(indicator)) {
                reactSignsFound++;
            }
        }

        if (reactSignsFound >= 2) {
            console.log(`   ✅ React app indicators found (${reactSignsFound}/${reactIndicators.length})`);
            results.tests.push({
                name: 'React App Indicators',
                status: 'PASS',
                details: `Found ${reactSignsFound} React-related patterns`
            });
        } else {
            console.log(`   ⚠️  Few React indicators (${reactSignsFound}/${reactIndicators.length})`);
            results.tests.push({
                name: 'React App Indicators',
                status: 'WARN',
                details: `Only found ${reactSignsFound} React-related patterns`
            });
        }

    } catch (error) {
        console.log(`   ❌ React check failed: ${error.message}`);
        results.tests.push({
            name: 'React App Indicators',
            status: 'FAIL',
            details: error.message
        });
    }

    // Summary
    console.log('\n📊 Test Summary');
    console.log('===============');
    const passed = results.tests.filter(t => t.status === 'PASS').length;
    const failed = results.tests.filter(t => t.status === 'FAIL').length;
    const warned = results.tests.filter(t => t.status === 'WARN').length;

    console.log(`✅ Passed: ${passed}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`⚠️  Warnings: ${warned}`);
    console.log(`\n🎯 Overall Status: ${results.overall_status}`);

    results.summary = `${passed} passed, ${failed} failed, ${warned} warnings`;

    // Save results
    const fs = require('fs');
    const path = require('path');
    const dir = '/home/lever/lever-protocol/control-plane/screenshots';

    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'basic-ui-test.json'), JSON.stringify(results, null, 2));

    return results.overall_status === 'PASS';
}

if (require.main === module) {
    basicUITest().then(success => {
        process.exit(success ? 0 : 1);
    }).catch(error => {
        console.error('❌ Test crashed:', error);
        process.exit(1);
    });
}

module.exports = { basicUITest };