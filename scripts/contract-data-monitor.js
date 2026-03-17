#!/usr/bin/env node

/**
 * Contract Data Pipeline Monitor & Error Handler
 *
 * This script specifically addresses the 413 RPC errors and data pipeline issues:
 * 1. Monitors contract data retrieval health
 * 2. Implements exponential backoff for failed calls
 * 3. Provides detailed logging of RPC errors
 * 4. Generates fallback data when primary calls fail
 * 5. Reports on data pipeline status for investor demo
 */

const { exec, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Load environment
require('dotenv').config();

// Contract data points to monitor
const CONTRACT_DATA_POINTS = [
    {
        name: 'TVL',
        contract: 'LEVER_VAULT',
        method: 'totalAssets()(uint256)',
        description: 'Total Value Locked',
        fallback: '60508028315742', // Current working value
        critical: true
    },
    {
        name: 'Global OI',
        contract: 'OI_LIMITS',
        method: 'getGlobalOI()(uint256)',
        description: 'Global Open Interest',
        fallback: '224222554735',
        critical: true
    },
    {
        name: 'Insurance Fund',
        contract: 'INSURANCE_FUND',
        method: 'getBalance()(uint256)',
        description: 'Insurance Fund Balance',
        fallback: '11000000000000000000000',
        critical: true
    },
    {
        name: 'Position Count',
        contract: 'POSITION_MANAGER',
        method: 'getActivePositionCount()(uint256)',
        description: 'Total Active Positions',
        fallback: '77',
        critical: false
    },
    {
        name: 'Platform Ceiling',
        contract: 'LEVERAGE_MODEL',
        method: 'getPlatformCeiling()(uint256)',
        description: 'Maximum Platform Leverage',
        fallback: '30000000000000000000', // 30 in WAD
        critical: false
    }
];

/**
 * Execute contract call with enhanced error handling
 */
async function executeContractCall(dataPoint, retryCount = 0) {
    const maxRetries = 3;
    const baseDelay = 1000; // 1 second

    return new Promise((resolve, reject) => {
        // Get environment variable for contract address
        const contractVar = dataPoint.contract;
        const command = `bash -c 'source /home/lever/lever-protocol/control-plane/deploy-env.sh && /home/lever/.foundry/bin/cast call $${contractVar} "${dataPoint.method}" --rpc-url $RPC_URL'`;

        const startTime = Date.now();

        exec(command, { timeout: 10000 }, (error, stdout, stderr) => {
            const endTime = Date.now();
            const duration = endTime - startTime;

            const result = {
                dataPoint: dataPoint.name,
                success: false,
                value: null,
                error: null,
                duration,
                retryCount,
                fallbackUsed: false
            };

            if (error) {
                const errorMsg = error.message + (stderr || '');
                result.error = errorMsg;

                // Check for specific error types
                const is413Error = errorMsg.includes('413') ||
                                  errorMsg.includes('Request Entity Too Large') ||
                                  errorMsg.includes('Payload Too Large');
                const isRateLimit = errorMsg.includes('rate limit') ||
                                   errorMsg.includes('too many requests') ||
                                   errorMsg.includes('429');
                const isNetworkError = errorMsg.includes('network') ||
                                      errorMsg.includes('timeout') ||
                                      errorMsg.includes('connection');

                console.log(`❌ ${dataPoint.name} failed (attempt ${retryCount + 1}): ${errorMsg.substring(0, 100)}...`);

                // Retry logic for retryable errors
                if ((is413Error || isRateLimit || isNetworkError) && retryCount < maxRetries) {
                    const retryDelay = baseDelay * Math.pow(2, retryCount) + Math.random() * 1000; // Exponential backoff with jitter
                    console.log(`🔄 Retrying ${dataPoint.name} in ${Math.round(retryDelay)}ms (attempt ${retryCount + 2}/${maxRetries + 1})`);

                    setTimeout(async () => {
                        try {
                            const retryResult = await executeContractCall(dataPoint, retryCount + 1);
                            resolve(retryResult);
                        } catch (retryError) {
                            result.error = retryError.message;
                            result.value = dataPoint.fallback;
                            result.fallbackUsed = true;
                            console.log(`🆘 Using fallback for ${dataPoint.name}: ${dataPoint.fallback}`);
                            resolve(result);
                        }
                    }, retryDelay);
                    return;
                }

                // Use fallback value for failed calls
                result.value = dataPoint.fallback;
                result.fallbackUsed = true;
                console.log(`🆘 Using fallback for ${dataPoint.name}: ${dataPoint.fallback}`);
            } else {
                const output = stdout.trim();
                if (output && !output.includes('Error') && !output.includes('revert')) {
                    result.success = true;
                    result.value = output;
                    console.log(`✅ ${dataPoint.name}: ${output} (${duration}ms)`);
                } else {
                    result.error = `Invalid output: ${output}`;
                    result.value = dataPoint.fallback;
                    result.fallbackUsed = true;
                    console.log(`⚠️ Invalid output for ${dataPoint.name}, using fallback: ${dataPoint.fallback}`);
                }
            }

            resolve(result);
        });
    });
}

/**
 * Monitor all contract data points
 */
async function monitorContractData() {
    console.log('📊 Contract Data Pipeline Monitor');
    console.log('=' .repeat(50));
    console.log(`Timestamp: ${new Date().toISOString()}`);
    console.log(`Monitoring ${CONTRACT_DATA_POINTS.length} data points...\n`);

    const results = {};
    const startTime = Date.now();

    // Execute all contract calls in parallel for efficiency
    const promises = CONTRACT_DATA_POINTS.map(async (dataPoint) => {
        console.log(`🔍 Checking ${dataPoint.name} (${dataPoint.description})...`);
        const result = await executeContractCall(dataPoint);
        results[dataPoint.name] = result;
        return result;
    });

    await Promise.all(promises);

    const endTime = Date.now();
    const totalDuration = endTime - startTime;

    // Analyze results
    const summary = analyzeResults(results, totalDuration);

    // Generate report
    const report = generateDataPipelineReport(results, summary);

    // Save report
    const reportPath = '/home/lever/lever-protocol/control-plane/contract-data-status.json';
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log('\n📈 Data Pipeline Status:');
    console.log(`Success Rate: ${summary.successRate}% (${summary.successCount}/${summary.totalCount})`);
    console.log(`Fallback Usage: ${summary.fallbackCount} data points`);
    console.log(`Total Duration: ${totalDuration}ms`);
    console.log(`Average Response Time: ${summary.avgResponseTime}ms`);

    if (summary.errors.length > 0) {
        console.log('\n❌ Errors Detected:');
        summary.errors.forEach(error => {
            console.log(`  • ${error.dataPoint}: ${error.type} - ${error.message.substring(0, 80)}...`);
        });
    }

    if (summary.fallbackCount > 0) {
        console.log('\n🆘 Fallback Values Used:');
        Object.values(results).filter(r => r.fallbackUsed).forEach(result => {
            console.log(`  • ${result.dataPoint}: ${result.value}`);
        });
    }

    console.log(`\n📄 Full report saved: ${reportPath}`);

    return report;
}

/**
 * Analyze monitoring results
 */
function analyzeResults(results, totalDuration) {
    const resultValues = Object.values(results);
    const totalCount = resultValues.length;
    const successCount = resultValues.filter(r => r.success).length;
    const fallbackCount = resultValues.filter(r => r.fallbackUsed).length;
    const successRate = Math.round((successCount / totalCount) * 100);

    const totalResponseTime = resultValues.reduce((sum, r) => sum + r.duration, 0);
    const avgResponseTime = Math.round(totalResponseTime / totalCount);

    const errors = resultValues
        .filter(r => r.error)
        .map(r => ({
            dataPoint: r.dataPoint,
            type: classify413Error(r.error),
            message: r.error
        }));

    return {
        totalCount,
        successCount,
        fallbackCount,
        successRate,
        avgResponseTime,
        totalDuration,
        errors,
        health: successRate >= 80 ? 'HEALTHY' :
                successRate >= 60 ? 'DEGRADED' : 'CRITICAL'
    };
}

/**
 * Classify error types for better debugging
 */
function classify413Error(errorMessage) {
    if (errorMessage.includes('413') || errorMessage.includes('Entity Too Large')) {
        return 'RPC_413_ERROR';
    }
    if (errorMessage.includes('rate limit') || errorMessage.includes('429')) {
        return 'RATE_LIMIT';
    }
    if (errorMessage.includes('timeout') || errorMessage.includes('network')) {
        return 'NETWORK_ERROR';
    }
    if (errorMessage.includes('revert') || errorMessage.includes('execution reverted')) {
        return 'CONTRACT_ERROR';
    }
    return 'UNKNOWN_ERROR';
}

/**
 * Generate comprehensive data pipeline report
 */
function generateDataPipelineReport(results, summary) {
    return {
        timestamp: new Date().toISOString(),
        pipeline_health: summary.health,
        success_rate: summary.successRate,
        fallback_usage: summary.fallbackCount,
        total_duration_ms: summary.totalDuration,
        avg_response_time_ms: summary.avgResponseTime,
        data_points: results,
        error_analysis: {
            rpc_413_errors: summary.errors.filter(e => e.type === 'RPC_413_ERROR').length,
            rate_limit_errors: summary.errors.filter(e => e.type === 'RATE_LIMIT').length,
            network_errors: summary.errors.filter(e => e.type === 'NETWORK_ERROR').length,
            contract_errors: summary.errors.filter(e => e.type === 'CONTRACT_ERROR').length,
            total_errors: summary.errors.length
        },
        recommendations: generateRecommendations(summary, results),
        investor_demo_ready: summary.successRate >= 80 && summary.fallbackCount <= 1
    };
}

/**
 * Generate recommendations based on monitoring results
 */
function generateRecommendations(summary, results) {
    const recommendations = [];

    if (summary.successRate < 60) {
        recommendations.push('CRITICAL: Data pipeline success rate below 60%. Investigate RPC connectivity issues.');
    }

    if (summary.errors.filter(e => e.type === 'RPC_413_ERROR').length > 0) {
        recommendations.push('ISSUE: 413 RPC errors detected. Consider implementing request batching or switching RPC providers.');
    }

    if (summary.errors.filter(e => e.type === 'RATE_LIMIT').length > 0) {
        recommendations.push('ISSUE: Rate limiting detected. Implement exponential backoff and consider premium RPC endpoint.');
    }

    if (summary.fallbackCount > 2) {
        recommendations.push('WARNING: High fallback usage may impact investor demo data accuracy.');
    }

    if (summary.avgResponseTime > 3000) {
        recommendations.push('PERFORMANCE: High average response time. Consider RPC endpoint optimization.');
    }

    if (summary.successRate >= 80 && summary.fallbackCount <= 1) {
        recommendations.push('READY: Data pipeline is investor demo ready with reliable data retrieval.');
    }

    return recommendations;
}

/**
 * Continuous monitoring mode
 */
async function continuousMonitoring(intervalMinutes = 5) {
    console.log(`🔄 Starting continuous monitoring (every ${intervalMinutes} minutes)...`);

    const interval = setInterval(async () => {
        try {
            console.log('\n' + '='.repeat(60));
            await monitorContractData();
            console.log('='.repeat(60));
        } catch (error) {
            console.error('❌ Monitoring cycle failed:', error);
        }
    }, intervalMinutes * 60 * 1000);

    // Initial run
    await monitorContractData();

    return interval;
}

/**
 * Main execution
 */
async function main() {
    const args = process.argv.slice(2);
    const isContinuous = args.includes('--continuous');
    const intervalMinutes = args.includes('--interval') ?
        parseInt(args[args.indexOf('--interval') + 1]) || 5 : 5;

    try {
        if (isContinuous) {
            await continuousMonitoring(intervalMinutes);
        } else {
            const report = await monitorContractData();

            // Exit with error code if pipeline is not healthy
            if (report.pipeline_health === 'CRITICAL') {
                process.exit(1);
            }
        }
    } catch (error) {
        console.error('❌ Contract data monitoring failed:', error);
        process.exit(1);
    }
}

// Run the script
if (require.main === module) {
    main();
}

module.exports = {
    executeContractCall,
    monitorContractData,
    analyzeResults
};