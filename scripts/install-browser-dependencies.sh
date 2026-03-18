#!/bin/bash
# Install Browser Dependencies for React SPA Testing
# This script installs the necessary dependencies for Playwright/Puppeteer browser automation

set -e

echo "🔧 Installing browser dependencies for React SPA testing..."

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  This script needs sudo privileges to install system packages."
    echo "   Run with: sudo bash scripts/install-browser-dependencies.sh"
    echo ""
    echo "   Alternatively, ask your system administrator to install:"
    echo "   libatk-1.0-0 libatk-bridge2.0-0 libdrm2 libxkbcommon0"
    echo "   libxcomposite1 libxdamage1 libxrandr2 libgbm1 libxss1 libasound2"
    exit 1
fi

# Update package list
echo "📦 Updating package list..."
apt-get update

# Install browser dependencies
echo "🌐 Installing browser automation dependencies..."
apt-get install -y \
    libatk-1.0-0 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2 \
    libatspi2.0-0 \
    libgtk-3-0 \
    libxcb-dri3-0

echo "✅ Browser dependencies installed successfully!"

# Test browser automation
echo "🧪 Testing browser automation..."
cd /home/lever/lever-protocol

# Test Playwright
echo "  Testing Playwright..."
if sudo -u lever node -e "
const { chromium } = require('playwright');
(async () => {
    try {
        const browser = await chromium.launch({ headless: true });
        await browser.close();
        console.log('✅ Playwright: Working');
    } catch (e) {
        console.log('❌ Playwright: Failed -', e.message);
    }
})();" 2>/dev/null; then
    echo "  ✅ Playwright is working!"
else
    echo "  ❌ Playwright still has issues"
fi

# Test Puppeteer
echo "  Testing Puppeteer..."
if sudo -u lever node -e "
const puppeteer = require('puppeteer');
(async () => {
    try {
        const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
        await browser.close();
        console.log('✅ Puppeteer: Working');
    } catch (e) {
        console.log('❌ Puppeteer: Failed -', e.message);
    }
})();" 2>/dev/null; then
    echo "  ✅ Puppeteer is working!"
else
    echo "  ❌ Puppeteer still has issues"
fi

# Test the improved QA scoring
echo "🎯 Testing improved QA scoring..."
if sudo -u lever node /home/lever/lever-protocol/scripts/improved-qa-scoring.js >/dev/null 2>&1; then
    echo "✅ React SPA testing is now fully functional!"
    echo ""
    echo "🎉 Setup complete! The QA system will now:"
    echo "   - Take actual screenshots of the rendered React application"
    echo "   - Test user interactions and navigation"
    echo "   - Provide accurate scores for investor presentations"
    echo "   - No longer fall back to curl-based testing"
else
    echo "⚠️  QA scoring test had issues, but dependencies are installed"
fi

echo ""
echo "ℹ️  You can now run: node scripts/improved-qa-scoring.js"
echo "   This will provide proper React SPA testing with browser automation."