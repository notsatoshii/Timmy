#!/usr/bin/env node

/**
 * RPC Reliability Check and Fallback Configuration
 *
 * This script:
 * 1. Tests multiple RPC endpoints for reliability
 * 2. Measures response times and error rates
 * 3. Sets up fallback RPC configuration
 * 4. Provides RPC health monitoring for the contract data pipeline
 */

const { spawn, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// Load environment
require('dotenv').config();

// RPC endpoints to test (Base Sepolia)
const RPC_ENDPOINTS = [
    {
        name: 'Base Sepolia (Official)',
        url: 'https://sepolia.base.org',
        primary: true
    },
    {
        name: 'Base Sepolia (Alchemy)',
        url: 'https://base-sepolia.g.alchemy.com/v2/demo',
        backup: true
    },
    {
        name: 'Base Sepolia (Infura)',
        url: 'https://base-sepolia.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161',
        backup: true
    },
    {
        name: 'Base Sepolia (BlockPI)',
        url: 'https://base-sepolia.blockpi.network/v1/rpc/public',
        backup: true
    }
];

// Contract to test with (LeverVault)
const TEST_CONTRACT = '0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921';

/**
 * Test RPC endpoint reliability
 */
async function testRPCEndpoint(endpoint) {
    console.log(`Testing ${endpoint.name}...`);

    const results = {
        name: endpoint.name,
        url: endpoint.url,
        success: 0,
        failed: 0,
        totalTime: 0,
        avgResponseTime: 0,
        errors: [],
        healthy: false
    };

    const NUM_TESTS = 5;

    for (let i = 0; i < NUM_TESTS; i++) {
        try {
            const startTime = Date.now();

            // Test basic eth_blockNumber call
            const response = await makeRPCCall(endpoint.url, {
                jsonrpc: '2.0',
                method: 'eth_blockNumber',
                params: [],
                id: 1
            });

            const endTime = Date.now();
            const responseTime = endTime - startTime;

            if (response && !response.error) {
                results.success++;
                results.totalTime += responseTime;
            } else {
                results.failed++;
                results.errors.push(response?.error || 'Unknown error');
            }
        } catch (error) {
            results.failed++;
            results.errors.push(error.message);
        }

        // Small delay between tests
        await new Promise(resolve => setTimeout(resolve, 100));
    }

    results.avgResponseTime = results.success > 0 ? Math.round(results.totalTime / results.success) : 0;
    results.healthy = results.success > (NUM_TESTS * 0.6); // 60% success rate

    console.log(`  ${endpoint.name}: ${results.success}/${NUM_TESTS} success, avg ${results.avgResponseTime}ms`);

    return results;
}

/**
 * Make RPC call with timeout
 */
function makeRPCCall(url, payload) {
    return new Promise((resolve, reject) => {
        const timeoutId = setTimeout(() => {
            reject(new Error('Request timeout'));
        }, 5000);

        fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
        })
        .then(response => response.json())
        .then(data => {
            clearTimeout(timeoutId);
            resolve(data);
        })
        .catch(error => {
            clearTimeout(timeoutId);
            reject(error);
        });
    });
}

/**
 * Test contract call with each endpoint
 */
async function testContractCalls(healthyEndpoints) {
    console.log('\nTesting contract calls...');

    const contractResults = {};

    for (const endpoint of healthyEndpoints) {
        console.log(`Testing contract calls on ${endpoint.name}...`);

        try {
            const castCommand = `bash -c 'source /home/lever/lever-protocol/control-plane/deploy-env.sh && /home/lever/.foundry/bin/cast call ${TEST_CONTRACT} "totalAssets()(uint256)" --rpc-url ${endpoint.url}'`;

            const result = await new Promise((resolve, reject) => {
                exec(castCommand, { timeout: 10000 }, (error, stdout, stderr) => {
                    if (error) {
                        reject(error);
                    } else {
                        resolve(stdout.trim());
                    }
                });
            });

            if (result && !result.includes('Error') && !result.includes('revert')) {
                contractResults[endpoint.url] = {
                    success: true,
                    result: result,
                    endpoint: endpoint.name
                };
                console.log(`  ✓ ${endpoint.name}: ${result}`);
            } else {
                contractResults[endpoint.url] = {
                    success: false,
                    error: result || 'Unknown error',
                    endpoint: endpoint.name
                };
                console.log(`  ✗ ${endpoint.name}: ${result || 'Failed'}`);
            }
        } catch (error) {
            contractResults[endpoint.url] = {
                success: false,
                error: error.message,
                endpoint: endpoint.name
            };
            console.log(`  ✗ ${endpoint.name}: ${error.message}`);
        }
    }

    return contractResults;
}

/**
 * Generate fallback RPC configuration
 */
function generateFallbackConfig(endpointResults, contractResults) {
    console.log('\nGenerating fallback RPC configuration...');

    // Sort endpoints by reliability
    const sortedEndpoints = endpointResults
        .filter(r => r.healthy)
        .sort((a, b) => {
            // Primary sort: contract call success
            const aContractSuccess = contractResults[a.url]?.success || false;
            const bContractSuccess = contractResults[b.url]?.success || false;
            if (aContractSuccess !== bContractSuccess) {
                return bContractSuccess ? 1 : -1;
            }

            // Secondary sort: response time
            return a.avgResponseTime - b.avgResponseTime;
        });

    const config = {
        timestamp: new Date().toISOString(),
        primary_rpc: sortedEndpoints[0]?.url || 'https://sepolia.base.org',
        fallback_rpcs: sortedEndpoints.slice(1).map(e => e.url),
        test_results: {
            endpoint_tests: endpointResults,
            contract_tests: contractResults
        },
        recommendations: []
    };

    // Add recommendations
    if (sortedEndpoints.length < 2) {
        config.recommendations.push('WARNING: Less than 2 healthy RPC endpoints found. Consider adding more providers.');
    }

    const primaryEndpoint = endpointResults.find(r => r.url === config.primary_rpc);
    if (primaryEndpoint && primaryEndpoint.avgResponseTime > 2000) {
        config.recommendations.push(`Primary RPC is slow (${primaryEndpoint.avgResponseTime}ms avg). Consider switching to faster endpoint.`);
    }

    if (sortedEndpoints.length > 0) {
        config.recommendations.push(`Found ${sortedEndpoints.length} healthy RPC endpoints. Fallback configuration ready.`);
    }

    return config;
}

/**
 * Create RPC fallback environment file
 */
function createRPCFallbackEnv(config) {
    const envContent = `# RPC Fallback Configuration
# Generated: ${config.timestamp}
# Auto-generated by rpc-reliability-check.js

# Primary RPC endpoint
export RPC_URL="${config.primary_rpc}"

# Fallback RPC endpoints (in priority order)
${config.fallback_rpcs.map((url, i) => `export RPC_FALLBACK_${i + 1}="${url}"`).join('\n')}

# RPC health check results
export RPC_HEALTH_CHECK_TIMESTAMP="${config.timestamp}"
export RPC_HEALTHY_ENDPOINTS=${config.fallback_rpcs.length + 1}
`;

    const envPath = '/home/lever/lever-protocol/control-plane/rpc-config.env';
    fs.writeFileSync(envPath, envContent);

    console.log(`\nRPC fallback configuration written to: ${envPath}`);
    return envPath;
}

/**
 * Create enhanced health check with better error handling
 */
function enhanceHealthCheckScript() {
    console.log('\nEnhancing health-check.sh with better error handling...');

    const healthCheckPath = '/home/lever/lever-protocol/control-plane/health-check.sh';
    const backupPath = healthCheckPath + '.backup';

    try {
        // Backup original
        let healthCheckContent = fs.readFileSync(healthCheckPath, 'utf8');
        fs.writeFileSync(backupPath, healthCheckContent);

        // Add RPC config source
        if (!healthCheckContent.includes('rpc-config.env')) {
            healthCheckContent = healthCheckContent.replace(
                'source /home/lever/lever-protocol/control-plane/deploy-env.sh',
                `source /home/lever/lever-protocol/control-plane/deploy-env.sh
source /home/lever/lever-protocol/control-plane/rpc-config.env 2>/dev/null || true`
            );
        }

        // Add error handling function for RPC calls
        const errorHandlingFunction = `
# Enhanced RPC call with fallback handling
rpc_call_with_fallback() {
    local cmd="$1"
    local fallback_rpcs=("$RPC_FALLBACK_1" "$RPC_FALLBACK_2" "$RPC_FALLBACK_3")

    # Try primary RPC first
    result=$(eval "$cmd" 2>&1)
    if ! echo "$result" | grep -qi "413\\|rate limit\\|timeout\\|network"; then
        echo "$result"
        return 0
    fi

    echo "WARN: Primary RPC failed with rate limit/network error, trying fallbacks..." >&2

    # Try fallback RPCs
    for fallback_rpc in "\${fallback_rpcs[@]}"; do
        if [ -n "$fallback_rpc" ]; then
            fallback_cmd=$(echo "$cmd" | sed "s|--rpc-url \\$RPC_URL|--rpc-url $fallback_rpc|g")
            result=$(eval "$fallback_cmd" 2>&1)
            if ! echo "$result" | grep -qi "413\\|rate limit\\|timeout\\|network"; then
                echo "INFO: Fallback RPC $fallback_rpc succeeded" >&2
                echo "$result"
                return 0
            fi
            sleep 1
        fi
    done

    echo "$result"
    return 1
}

`;

        // Insert the function after the check() function
        healthCheckContent = healthCheckContent.replace(
            'check() {',
            errorHandlingFunction + 'check() {'
        );

        // Replace critical data pipeline calls with fallback-aware versions
        const criticalCallPatterns = [
            { pattern: /\$CAST call \$LEVER_VAULT 'totalAssets\(\)\(uint256\)' --rpc-url \$RPC_URL/g,
              replacement: 'rpc_call_with_fallback "$CAST call $LEVER_VAULT \'totalAssets()(uint256)\' --rpc-url $RPC_URL"' },
            { pattern: /\$CAST call \$OI_LIMITS 'getGlobalOI\(\)\(uint256\)' --rpc-url \$RPC_URL/g,
              replacement: 'rpc_call_with_fallback "$CAST call $OI_LIMITS \'getGlobalOI()(uint256)\' --rpc-url $RPC_URL"' },
            { pattern: /\$CAST call \$INSURANCE_FUND 'getBalance\(\)\(uint256\)' --rpc-url \$RPC_URL/g,
              replacement: 'rpc_call_with_fallback "$CAST call $INSURANCE_FUND \'getBalance()(uint256)\' --rpc-url $RPC_URL"' },
            { pattern: /\$CAST call \$LEVERAGE_MODEL 'getPlatformCeiling\(\)\(uint256\)' --rpc-url \$RPC_URL/g,
              replacement: 'rpc_call_with_fallback "$CAST call $LEVERAGE_MODEL \'getPlatformCeiling()(uint256)\' --rpc-url $RPC_URL"' }
        ];

        for (const { pattern, replacement } of criticalCallPatterns) {
            healthCheckContent = healthCheckContent.replace(pattern, replacement);
        }

        fs.writeFileSync(healthCheckPath, healthCheckContent);
        console.log('Health check script enhanced with RPC fallback handling');
        console.log(`Backup saved to: ${backupPath}`);

    } catch (error) {
        console.error('Failed to enhance health-check.sh:', error.message);
    }
}

/**
 * Main execution
 */
async function main() {
    console.log('🔍 RPC Reliability Check and Fallback Configuration');
    console.log('=' .repeat(60));

    try {
        // Test all RPC endpoints
        console.log('\n1. Testing RPC endpoint reliability...');
        const endpointResults = [];

        for (const endpoint of RPC_ENDPOINTS) {
            const result = await testRPCEndpoint(endpoint);
            endpointResults.push(result);
        }

        // Filter healthy endpoints
        const healthyEndpoints = endpointResults.filter(r => r.healthy);

        if (healthyEndpoints.length === 0) {
            console.error('\n❌ No healthy RPC endpoints found!');
            // Still generate config with original endpoint
            const fallbackConfig = {
                timestamp: new Date().toISOString(),
                primary_rpc: 'https://sepolia.base.org',
                fallback_rpcs: [],
                test_results: { endpoint_tests: endpointResults, contract_tests: {} },
                recommendations: ['WARNING: All RPC endpoints failed during testing. Using default endpoint.']
            };
            createRPCFallbackEnv(fallbackConfig);
            enhanceHealthCheckScript();
            return;
        }

        console.log(`\n✓ Found ${healthyEndpoints.length} healthy RPC endpoints`);

        // Test contract calls
        console.log('\n2. Testing contract calls...');
        const contractResults = await testContractCalls(healthyEndpoints);

        // Generate configuration
        console.log('\n3. Generating fallback configuration...');
        const config = generateFallbackConfig(endpointResults, contractResults);

        // Create configuration files
        const envPath = createRPCFallbackEnv(config);
        enhanceHealthCheckScript();

        // Save full results
        const resultsPath = '/home/lever/lever-protocol/control-plane/rpc-health-results.json';
        fs.writeFileSync(resultsPath, JSON.stringify(config, null, 2));

        console.log('\n📊 Results Summary:');
        console.log(`Primary RPC: ${config.primary_rpc}`);
        console.log(`Fallback RPCs: ${config.fallback_rpcs.length}`);
        console.log(`Configuration: ${envPath}`);
        console.log(`Full results: ${resultsPath}`);

        if (config.recommendations.length > 0) {
            console.log('\n💡 Recommendations:');
            config.recommendations.forEach(rec => console.log(`  • ${rec}`));
        }

        console.log('\n✅ RPC reliability configuration complete!');
        console.log('The contract data pipeline now has improved error handling and fallback RPCs.');

    } catch (error) {
        console.error('\n❌ RPC reliability check failed:', error);
        process.exit(1);
    }
}

// Add fetch polyfill for Node.js
if (typeof fetch === 'undefined') {
    global.fetch = require('node-fetch');
}

// Run the script
if (require.main === module) {
    main();
}

module.exports = {
    testRPCEndpoint,
    makeRPCCall,
    generateFallbackConfig
};