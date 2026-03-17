#!/usr/bin/env node
/**
 * Debug Frontend Loading Issues
 * Analyzes what's actually being served and identifies potential React mounting issues
 */

const http = require('http');
const fs = require('fs');

async function debugFrontendLoading() {
  console.log('🔍 Debugging Frontend Loading Issues...\n');

  // Test 1: Get the actual HTML being served
  console.log('1. Analyzing served HTML content...');

  const html = await new Promise((resolve, reject) => {
    http.get('http://localhost:3000', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });

  console.log(`   HTML length: ${html.length} characters`);

  // Test 2: Check the main JavaScript file
  console.log('\n2. Checking main JavaScript bundle...');

  // Extract JS file path from HTML
  const jsMatch = html.match(/src="([^"]*main\.[^"]*\.js)"/);
  if (!jsMatch) {
    console.log('   ✗ No main.js file reference found in HTML');
    return false;
  }

  const jsPath = jsMatch[1];
  console.log(`   Found JS file: ${jsPath}`);

  const jsContent = await new Promise((resolve, reject) => {
    http.get(`http://localhost:3000${jsPath}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });

  console.log(`   JS bundle size: ${jsContent.length} characters`);

  // Test 3: Check for React-specific content in JS bundle
  console.log('\n3. Analyzing JavaScript bundle content...');

  const reactChecks = [
    { name: 'React import', pattern: 'react' },
    { name: 'ReactDOM', pattern: 'ReactDOM' },
    { name: 'createElement', pattern: 'createElement' },
    { name: 'Component', pattern: 'Component' },
    { name: 'useState', pattern: 'useState' },
    { name: 'DashboardOptimized', pattern: 'DashboardOptimized' },
    { name: 'WagmiProvider', pattern: 'WagmiProvider' },
    { name: 'QueryClient', pattern: 'QueryClient' }
  ];

  let foundReactFeatures = 0;
  reactChecks.forEach(check => {
    if (jsContent.toLowerCase().includes(check.pattern.toLowerCase())) {
      console.log(`   ✓ ${check.name} found in bundle`);
      foundReactFeatures++;
    } else {
      console.log(`   ✗ ${check.name} NOT found in bundle`);
    }
  });

  // Test 4: Check for common build/compilation issues
  console.log('\n4. Checking for build issues...');

  const buildIssues = [
    { name: 'Syntax errors', pattern: 'SyntaxError', isError: true },
    { name: 'Module not found', pattern: 'Module not found', isError: true },
    { name: 'Cannot resolve', pattern: 'Cannot resolve', isError: true },
    { name: 'Webpack errors', pattern: 'webpack', isError: false },
    { name: 'React errors', pattern: 'React', isError: false },
    { name: 'Development mode', pattern: 'development', isError: false }
  ];

  let foundBuildIssues = 0;
  buildIssues.forEach(check => {
    if (jsContent.toLowerCase().includes(check.pattern.toLowerCase())) {
      const symbol = check.isError ? '⚠️' : '📍';
      console.log(`   ${symbol} ${check.name} found in bundle`);
      if (check.isError) foundBuildIssues++;
    }
  });

  // Test 5: Check build directory structure
  console.log('\n5. Checking build directory structure...');

  try {
    const staticDir = fs.readdirSync('/home/lever/lever-protocol/frontend/user-app/build/static');
    console.log(`   Static directory exists with: ${staticDir.join(', ')}`);

    const jsDir = fs.readdirSync('/home/lever/lever-protocol/frontend/user-app/build/static/js');
    console.log(`   JS directory has ${jsDir.length} files`);

    const cssDir = fs.readdirSync('/home/lever/lever-protocol/frontend/user-app/build/static/css');
    console.log(`   CSS directory has ${cssDir.length} files`);
  } catch (error) {
    console.log(`   ✗ Error reading build directory: ${error.message}`);
  }

  // Test 6: Check for runtime configuration issues
  console.log('\n6. Checking for configuration issues...');

  try {
    const configFile = '/home/lever/lever-protocol/frontend/user-app/src/config/contracts.ts';
    if (fs.existsSync(configFile)) {
      const configContent = fs.readFileSync(configFile, 'utf8');
      console.log(`   ✓ Config file exists (${configContent.length} chars)`);

      // Check for potential configuration issues
      if (configContent.includes('0x0') || configContent.includes('undefined')) {
        console.log('   ⚠️  Potential undefined contract addresses in config');
      } else {
        console.log('   ✓ Contract configuration appears valid');
      }
    } else {
      console.log('   ✗ Configuration file not found');
    }
  } catch (error) {
    console.log(`   ⚠️  Error checking config: ${error.message}`);
  }

  // Test 7: Create a simple HTML test file
  console.log('\n7. Creating standalone test file...');

  const testHTML = `<!DOCTYPE html>
<html>
<head>
    <title>LEVER React Test</title>
    <script>
        // Simple test to check if React bundle loads
        console.log('Test HTML loaded');

        // Load the main bundle and test
        const script = document.createElement('script');
        script.src = '${jsPath}';
        script.onload = () => {
            console.log('React bundle loaded successfully');
            setTimeout(() => {
                const rootEl = document.getElementById('root');
                if (rootEl && rootEl.innerHTML.length > 100) {
                    console.log('✅ React app rendered successfully');
                } else {
                    console.log('❌ React app did not render');
                }
            }, 2000);
        };
        script.onerror = (err) => {
            console.log('❌ Error loading React bundle:', err);
        };
        document.head.appendChild(script);
    </script>
</head>
<body>
    <div id="root">Loading...</div>
    <p>If you see this and the div above is empty, React is not mounting.</p>
</body>
</html>`;

  fs.writeFileSync('/home/lever/lever-protocol/frontend/user-app/build/test.html', testHTML);
  console.log('   ✓ Test file created at /test.html');
  console.log('   📍 Visit http://localhost:3000/test.html to debug');

  // Summary
  console.log('\n📊 Debug Summary:');
  console.log(`   React features in bundle: ${foundReactFeatures}/${reactChecks.length}`);
  console.log(`   Build issues found: ${foundBuildIssues}`);

  if (foundReactFeatures < 5) {
    console.log('\n❌ ISSUE: React components missing from bundle - possible build failure');
    return false;
  } else if (foundBuildIssues > 0) {
    console.log('\n⚠️  ISSUE: Build problems detected - may prevent React from running');
    return false;
  } else {
    console.log('\n✅ React bundle appears to be built correctly');
    console.log('   If React still not mounting, it may be a runtime issue');
    return true;
  }
}

debugFrontendLoading().then(success => {
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('Debug failed:', error);
  process.exit(1);
});