#!/usr/bin/env node
/**
 * Test if React app actually mounts by creating a simple test page
 * and checking if the root div gets populated
 */

const http = require('http');
const fs = require('fs');

async function testReactMount() {
  console.log('🔬 Testing React App Mounting...\n');

  // Step 1: Create a test page that includes all the same resources
  console.log('1. Creating test page...');

  // Get the main page to extract the correct asset paths
  const mainPage = await new Promise((resolve, reject) => {
    http.get('http://localhost:3000', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });

  // Extract asset paths from main page
  const jsMatch = mainPage.match(/src="([^"]*main\.[^"]*\.js)"/);
  const cssMatch = mainPage.match(/href="([^"]*main\.[^"]*\.css)"/);

  if (!jsMatch || !cssMatch) {
    console.log('   ✗ Could not extract asset paths from main page');
    return false;
  }

  const jsPath = jsMatch[1];
  const cssPath = cssMatch[1];
  console.log(`   ✓ JS path: ${jsPath}`);
  console.log(`   ✓ CSS path: ${cssPath}`);

  // Create test page with debug functionality
  const testHTML = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>LEVER React Mount Test</title>
    <link href="${cssPath}" rel="stylesheet">
    <style>
        body { font-family: system-ui; padding: 20px; background: #0f172a; color: #e2e8f0; }
        .test-info { border: 1px solid #333; padding: 15px; margin: 10px 0; border-radius: 8px; }
        .success { border-color: #10b981; background: rgba(16, 185, 129, 0.1); }
        .error { border-color: #ef4444; background: rgba(239, 68, 68, 0.1); }
        .pending { border-color: #f59e0b; background: rgba(245, 158, 11, 0.1); }
    </style>
</head>
<body>
    <h1>LEVER React Mount Test</h1>

    <div id="test-status" class="test-info pending">
        <h3>Status: Loading...</h3>
        <p>Waiting for React bundle to load and mount...</p>
    </div>

    <div id="mount-checks" class="test-info pending">
        <h3>Mount Checks:</h3>
        <ul id="check-list">
            <li>❓ React bundle loading...</li>
        </ul>
    </div>

    <div id="root">
        <div style="padding: 20px; text-align: center; color: #64748b;">
            If React mounts properly, this placeholder will be replaced with the LEVER dashboard.
        </div>
    </div>

    <script>
        const statusDiv = document.getElementById('test-status');
        const checkList = document.getElementById('check-list');

        function updateStatus(message, type = 'pending') {
            statusDiv.className = 'test-info ' + type;
            statusDiv.innerHTML = '<h3>Status: ' + message + '</h3>';
        }

        function addCheck(message, type = 'pending') {
            const li = document.createElement('li');
            li.textContent = message;
            checkList.appendChild(li);
        }

        // Track React mounting process
        let startTime = Date.now();
        let reactLoaded = false;
        let reactMounted = false;

        function checkReactMount() {
            const rootEl = document.getElementById('root');
            const hasReactContent = rootEl && rootEl.children.length > 0 &&
                                  !rootEl.innerHTML.includes('placeholder will be replaced');

            if (hasReactContent) {
                if (!reactMounted) {
                    reactMounted = true;
                    const mountTime = Date.now() - startTime;
                    addCheck('✅ React mounted successfully in ' + mountTime + 'ms', 'success');
                    updateStatus('React App Mounted Successfully!', 'success');

                    // Check for specific components
                    setTimeout(() => {
                        const hasNavigationTabs = document.querySelector('.md\\\\:flex') ||
                                                document.querySelector('button') ||
                                                document.querySelector('[role="tab"]');
                        const hasMainContent = document.querySelector('main') ||
                                             document.querySelector('.dashboard') ||
                                             document.querySelector('.min-h-screen');

                        if (hasNavigationTabs) addCheck('✅ Navigation tabs rendered');
                        if (hasMainContent) addCheck('✅ Main content area rendered');

                        // Final verdict
                        if (hasNavigationTabs && hasMainContent) {
                            updateStatus('✅ Full React App Working!', 'success');
                        } else {
                            updateStatus('⚠️ React mounted but missing components', 'error');
                        }
                    }, 500);
                }
                return true;
            }
            return false;
        }

        // Monitor console for errors
        const originalConsoleError = console.error;
        console.error = function(...args) {
            addCheck('❌ Console Error: ' + args.join(' '));
            originalConsoleError.apply(console, arguments);
        };

        // Load React bundle
        console.log('Loading React bundle...');
        const script = document.createElement('script');
        script.src = '${jsPath}';

        script.onload = function() {
            reactLoaded = true;
            addCheck('✅ React bundle loaded');
            updateStatus('Bundle loaded, checking for React mount...', 'pending');

            // Check for React mount repeatedly
            let checkCount = 0;
            const checkInterval = setInterval(() => {
                checkCount++;

                if (checkReactMount()) {
                    clearInterval(checkInterval);
                } else if (checkCount > 40) { // 4 seconds
                    clearInterval(checkInterval);
                    addCheck('❌ React failed to mount within 4 seconds');
                    updateStatus('React Bundle Loaded but Failed to Mount', 'error');

                    // Additional debugging
                    addCheck('🔍 Root div content: ' + document.getElementById('root').innerHTML.substring(0, 100) + '...');
                }
            }, 100);
        };

        script.onerror = function(error) {
            addCheck('❌ Failed to load React bundle');
            updateStatus('Failed to Load React Bundle', 'error');
            console.error('Script load error:', error);
        };

        document.head.appendChild(script);

        // Timeout for overall test
        setTimeout(() => {
            if (!reactMounted) {
                updateStatus('Test Timeout - React Did Not Mount', 'error');
            }
        }, 10000);
    </script>
</body>
</html>`;

  // Write test file
  const testPath = '/home/lever/lever-protocol/frontend/user-app/build/react-test.html';
  fs.writeFileSync(testPath, testHTML);
  console.log('   ✓ Test page created');

  // Step 2: Wait a moment for the service to serve the new file
  await new Promise(resolve => setTimeout(resolve, 1000));

  // Step 3: Access the test page to trigger React loading
  console.log('\n2. Loading test page and monitoring React mount...');

  try {
    const testResponse = await new Promise((resolve, reject) => {
      http.get('http://localhost:3000/react-test.html', (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data }));
      }).on('error', reject);
    });

    console.log(`   ✓ Test page loaded (${testResponse.status})`);
    console.log(`   📄 Test page available at: http://localhost:3000/react-test.html`);

    // Step 4: Instructions for manual verification
    console.log('\n3. Manual verification required:');
    console.log('   📍 Open http://localhost:3000/react-test.html in your browser');
    console.log('   📍 The page will automatically test React mounting and show results');
    console.log('   📍 Look for green "React App Mounted Successfully!" status');

    // Step 5: Also test the original page for comparison
    console.log('\n4. Testing original page structure...');

    const originalContent = await new Promise((resolve, reject) => {
      http.get('http://localhost:3000', (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });

    // Check if the original page has obvious signs that React should be working
    const hasReactRoot = originalContent.includes('<div id="root">');
    const hasReactBundle = originalContent.includes('/static/js/main.');
    const hasTitleCorrect = originalContent.includes('LEVER Protocol');

    console.log(`   ✓ React root div: ${hasReactRoot ? 'Found' : 'Missing'}`);
    console.log(`   ✓ React bundle link: ${hasReactBundle ? 'Found' : 'Missing'}`);
    console.log(`   ✓ Correct title: ${hasTitleCorrect ? 'Found' : 'Missing'}`);

    if (hasReactRoot && hasReactBundle && hasTitleCorrect) {
      console.log('\n✅ Frontend structure appears correct');
      console.log('   The issue is likely that React bundle loads but fails to mount');
      console.log('   Use the test page to debug mounting issues');
      return true;
    } else {
      console.log('\n❌ Frontend structure has issues');
      return false;
    }

  } catch (error) {
    console.log(`   ✗ Error loading test page: ${error.message}`);
    return false;
  }
}

testReactMount().then(success => {
  console.log('\n📊 Test Summary:');
  console.log(success ? '✅ Frontend ready for React testing' : '❌ Frontend has structural issues');
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('\n❌ Test failed:', error.message);
  process.exit(1);
});