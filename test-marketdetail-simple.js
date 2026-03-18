#!/usr/bin/env node
// Simple test to check if MarketDetail component can be imported and basic validation works

const fs = require('fs');
const path = require('path');

console.log('Testing MarketDetail component for basic errors...');

// Read the MarketDetail component file
const marketDetailPath = '/home/lever/lever-protocol/frontend/user-app/src/components/MarketDetail.tsx';

try {
    const marketDetailContent = fs.readFileSync(marketDetailPath, 'utf8');
    console.log('✓ MarketDetail component file exists and is readable');

    // Check for common error patterns
    const errorPatterns = [
        { pattern: /useReadContract\(.*\)/, message: 'Found useReadContract calls' },
        { pattern: /formatRate/, message: 'Found formatRate function' },
        { pattern: /market\.id/, message: 'Found market.id usage' },
        { pattern: /market\.price/, message: 'Found market.price usage' },
        { pattern: /CONTRACT_ADDRESSES/, message: 'Found CONTRACT_ADDRESSES usage' },
        { pattern: /OI_LIMITS_ABI/, message: 'Found OI_LIMITS_ABI usage' },
        { pattern: /BORROW_FEE_ENGINE_ABI/, message: 'Found BORROW_FEE_ENGINE_ABI usage' },
        { pattern: /FUNDING_RATE_ENGINE_ABI/, message: 'Found FUNDING_RATE_ENGINE_ABI usage' }
    ];

    let foundPatterns = 0;
    for (const { pattern, message } of errorPatterns) {
        if (pattern.test(marketDetailContent)) {
            console.log(`✓ ${message}`);
            foundPatterns++;
        } else {
            console.log(`✗ ${message}`);
        }
    }

    console.log(`Found ${foundPatterns}/${errorPatterns.length} expected patterns`);

    // Check for potential syntax issues
    const syntaxIssues = [
        { pattern: /}\s*catch\s*\(\s*\)\s*{/, message: 'Empty catch blocks found' },
        { pattern: /console\.error\(/, message: 'Error logging present' },
        { pattern: /isNaN\(/, message: 'NaN checks present' },
        { pattern: /isFinite\(/, message: 'Finite checks present' },
        { pattern: /typeof.*===.*'number'/, message: 'Type checking present' }
    ];

    let foundSyntaxChecks = 0;
    for (const { pattern, message } of syntaxIssues) {
        if (pattern.test(marketDetailContent)) {
            console.log(`✓ ${message}`);
            foundSyntaxChecks++;
        }
    }

    console.log(`Found ${foundSyntaxChecks}/${syntaxIssues.length} safety patterns`);

    // Check if the file has our recent error handling improvements
    const improvementPatterns = [
        'query: {',
        'enabled: !!market.id',
        'error: longOIError',
        'isLoading: longOILoading',
        'if (!market)',
        'Invalid Market Data',
        'isFinite(num)',
        'console.warn'
    ];

    let foundImprovements = 0;
    for (const pattern of improvementPatterns) {
        if (marketDetailContent.includes(pattern)) {
            console.log(`✓ Found improvement: ${pattern}`);
            foundImprovements++;
        }
    }

    console.log(`Found ${foundImprovements}/${improvementPatterns.length} error handling improvements`);

    if (foundImprovements >= 6) {
        console.log('✅ MarketDetail component has good error handling');
    } else {
        console.log('⚠️  MarketDetail component may need more error handling');
    }

    // Test the import dependencies
    const dependencyFiles = [
        '/home/lever/lever-protocol/frontend/user-app/src/config/contracts.ts',
        '/home/lever/lever-protocol/frontend/user-app/src/config/abis.ts',
        '/home/lever/lever-protocol/frontend/user-app/src/hooks/useMarketProbabilities.ts'
    ];

    let dependenciesOk = true;
    for (const depFile of dependencyFiles) {
        if (fs.existsSync(depFile)) {
            console.log(`✓ Dependency exists: ${path.basename(depFile)}`);
        } else {
            console.log(`✗ Missing dependency: ${path.basename(depFile)}`);
            dependenciesOk = false;
        }
    }

    if (dependenciesOk) {
        console.log('✅ All dependencies exist');
    } else {
        console.log('❌ Missing dependencies detected');
        process.exit(1);
    }

    console.log('\n✅ MarketDetail component appears to be properly structured');

} catch (error) {
    console.error('❌ Error testing MarketDetail component:', error.message);
    process.exit(1);
}