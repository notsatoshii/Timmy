const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

async function generateOGImage() {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();

  // Set viewport to exact OG image dimensions
  await page.setViewport({ width: 1200, height: 630 });

  // Read the SVG logo
  const logoSvg = fs.readFileSync(path.join(__dirname, 'public', 'lever-logo.svg'), 'utf8');

  // Create HTML content for the OG image
  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        body {
          width: 1200px;
          height: 630px;
          background: linear-gradient(135deg, #0f0f23 0%, #1e1b4b 50%, #312e81 100%);
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
          color: white;
          overflow: hidden;
          position: relative;
        }
        .logo-container {
          width: 600px;
          height: auto;
          margin-bottom: 40px;
          filter: brightness(1.1);
        }
        .logo-container svg {
          width: 100%;
          height: auto;
        }
        .title {
          font-size: 48px;
          font-weight: 800;
          margin-bottom: 20px;
          background: linear-gradient(135deg, #a7f3d0 0%, #34d399 50%, #10b981 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
          text-align: center;
        }
        .subtitle {
          font-size: 24px;
          font-weight: 400;
          color: #e5e7eb;
          text-align: center;
          opacity: 0.9;
          max-width: 800px;
        }
        .background-pattern {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          opacity: 0.1;
          background-image:
            radial-gradient(circle at 25% 25%, #a7f3d0 2px, transparent 2px),
            radial-gradient(circle at 75% 75%, #34d399 1px, transparent 1px);
          background-size: 60px 60px;
          z-index: 0;
        }
        .content {
          position: relative;
          z-index: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
        }
      </style>
    </head>
    <body>
      <div class="background-pattern"></div>
      <div class="content">
        <div class="logo-container">
          ${logoSvg}
        </div>
        <h1 class="title">LEVER PROTOCOL</h1>
        <p class="subtitle">Synthetic Leveraged Perpetuals on Prediction Markets</p>
      </div>
    </body>
    </html>
  `;

  // Set the HTML content
  await page.setContent(html, { waitUntil: 'networkidle0' });

  // Take screenshot
  await page.screenshot({
    path: path.join(__dirname, 'public', 'lever-og-image.png'),
    type: 'png',
    clip: { x: 0, y: 0, width: 1200, height: 630 }
  });

  await browser.close();
  console.log('✅ Generated lever-og-image.png successfully!');
}

generateOGImage().catch(console.error);