// Test script to check if MarketDetail crashes when clicking market cards
const puppeteer = require('puppeteer');

(async () => {
    let browser;
    try {
        browser = await puppeteer.launch({
            headless: "new",
            executablePath: "/usr/bin/chromium-browser",
            args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
        });

        const page = await browser.newPage();
        await page.setViewport({ width: 1440, height: 900 });

        console.log('Opening frontend...');
        await page.goto("http://localhost:3000", { waitUntil: "networkidle2", timeout: 30000 });
        await new Promise(r => setTimeout(r, 5000)); // Wait for markets to load

        console.log('Taking screenshot of Markets tab...');
        await page.screenshot({
            path: "/home/lever/lever-protocol/control-plane/screenshots/markets-tab.png",
            fullPage: true
        });

        // Check if we're on the Markets tab (should be default)
        const marketsTabActive = await page.evaluate(() => {
            const body = document.body.innerText;
            return body.includes('Prediction Markets') && body.includes('Browse active binary outcome markets');
        });

        console.log('Markets tab loaded:', marketsTabActive);

        // Look for market cards
        const marketCards = await page.$$('.bg-surface-1.rounded-lg.border.border-border.p-5');
        console.log('Found market cards:', marketCards.length);

        if (marketCards.length === 0) {
            console.log('ERROR: No market cards found');
            return;
        }

        // Click on the first market card
        console.log('Clicking on first market card...');
        await marketCards[0].click();

        // Wait a bit for the MarketDetail component to load
        await new Promise(r => setTimeout(r, 3000));

        console.log('Taking screenshot after market card click...');
        await page.screenshot({
            path: "/home/lever/lever-protocol/control-plane/screenshots/marketdetail-test.png",
            fullPage: true
        });

        // Check if we're now on MarketDetail page (should have Back to Markets button)
        const onMarketDetail = await page.evaluate(() => {
            const body = document.body.innerText;
            return body.includes('Back to Markets');
        });

        // Check if there's an error boundary
        const hasErrorBoundary = await page.evaluate(() => {
            const body = document.body.innerText;
            return body.includes('Panel Error') || body.includes('Something went wrong');
        });

        console.log('On MarketDetail page:', onMarketDetail);
        console.log('Error boundary visible:', hasErrorBoundary);

        if (hasErrorBoundary) {
            console.log('ERROR: MarketDetail component crashed and error boundary is showing');
            // Get the error details
            const errorText = await page.evaluate(() => {
                return document.body.innerText;
            });
            console.log('Error text:', errorText.substring(0, 500) + '...');
            process.exit(1);
        } else if (onMarketDetail) {
            console.log('SUCCESS: MarketDetail component loaded successfully');
        } else {
            console.log('ERROR: Neither MarketDetail nor error boundary found - unexpected state');
            process.exit(1);
        }

    } catch (error) {
        console.log('ERROR during test:', error.message);
        process.exit(1);
    } finally {
        if (browser) {
            await browser.close();
        }
    }
})();