const http = require('http');

console.log('Testing frontend position values...');

// Simple HTTP request to get the page content
const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/',
  method: 'GET',
  headers: {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
  }
};

const req = http.request(options, (res) => {
  let data = '';

  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    console.log('HTTP Status:', res.statusCode);

    // Check if the page loads
    if (data.includes('LEVER Protocol')) {
      console.log('✓ Frontend loaded successfully');
    } else {
      console.log('✗ Frontend not loaded properly');
    }

    // Since React renders dynamically, we can't check for position values in the initial HTML
    // But we can at least verify the page structure is there
    if (data.includes('main.e85489e6.js') || data.includes('main.')) {
      console.log('✓ JavaScript bundle found - React should render positions');
    } else {
      console.log('✗ JavaScript bundle not found');
    }

    // Log a portion of the response for debugging
    console.log('\nHTML snippet (first 500 chars):');
    console.log(data.substring(0, 500));

    console.log('\nTo verify position values manually:');
    console.log('1. Open http://localhost:3000 in a browser');
    console.log('2. Open browser developer console (F12)');
    console.log('3. Look for [Positions] debug logs');
    console.log('4. Check if position values show as non-zero dollars');
    console.log('5. Demo positions should show when no wallet is connected');
  });
});

req.on('error', (e) => {
  console.error(`Request error: ${e.message}`);
});

req.end();