const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
const PAGES = [
  { name: 'markets', path: '/', waitFor: 2000 },
  { name: 'trading', path: '/#/trading', waitFor: 2000 },
  { name: 'vault', path: '/#/vault', waitFor: 2000 },
  { name: 'positions', path: '/#/positions', waitFor: 2000 },
];
const SIZES = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'mobile', width: 375, height: 812 },
];
(async () => {
  const browser = await puppeteer.launch({ headless: 'new', executablePath: '/usr/bin/chromium-browser', args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  const outDir = '/home/lever/lever-protocol/frontend/screenshots';
  fs.mkdirSync(outDir, { recursive: true });
  for (const size of SIZES) {
    const page = await browser.newPage();
    await page.setViewport({ width: size.width, height: size.height });
    for (const pg of PAGES) {
      try {
        await page.goto('http://localhost:3000' + pg.path, { waitUntil: 'networkidle0', timeout: 15000 });
        await new Promise(r => setTimeout(r, pg.waitFor));
        await page.screenshot({ path: path.join(outDir, pg.name + '-' + size.name + '.png'), fullPage: true });
        console.log('Captured: ' + pg.name + '-' + size.name);
      } catch (e) { console.error('Failed: ' + pg.name + '-' + size.name + ': ' + e.message); }
    }
    await page.close();
  }
  await browser.close();
})();
