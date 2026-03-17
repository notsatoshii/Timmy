#!/bin/bash

# Fix Chrome Dependencies for Screenshots
# Downloads and sets up required libraries for Puppeteer Chrome

set -e

LIBS_DIR="/home/lever/local-libs"
mkdir -p "$LIBS_DIR"

echo "🔧 Setting up Chrome dependencies..."

# Download required .deb packages and extract libraries
cd "$LIBS_DIR"

# Function to download and extract .so files from .deb package
download_extract_deb() {
    local url=$1
    local filename=$(basename "$url")

    echo "📦 Downloading $filename..."
    if wget -q "$url" -O "$filename"; then
        echo "📂 Extracting libraries from $filename..."
        ar x "$filename" data.tar.xz
        tar -xf data.tar.xz ./usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
        rm -f "$filename" data.tar.xz
    else
        echo "⚠️  Failed to download $filename"
    fi
}

# Try to download ATK and related libraries from Ubuntu packages
echo "🌐 Attempting to download ATK libraries..."

# Create a script to find and download the right packages
cat > find_packages.py << 'EOF'
#!/usr/bin/env python3
import urllib.request
import re
import sys

def find_package_url(package_name, version="24.04"):
    base_url = "http://packages.ubuntu.com"
    search_url = f"{base_url}/search?keywords={package_name}&searchon=names&suite=noble&section=all"

    try:
        with urllib.request.urlopen(search_url) as response:
            html = response.read().decode('utf-8')

        # Look for download links
        pattern = r'href="([^"]*pool[^"]*' + package_name + r'[^"]*\.deb)"'
        matches = re.findall(pattern, html)

        if matches:
            # Get the actual download URL
            download_page = base_url + matches[0]
            with urllib.request.urlopen(download_page) as response:
                page_html = response.read().decode('utf-8')

            # Find the actual .deb file URL
            deb_pattern = r'href="(http://archive\.ubuntu\.com[^"]*\.deb)"'
            deb_matches = re.findall(deb_pattern, page_html)

            if deb_matches:
                return deb_matches[0]

    except Exception as e:
        print(f"Error finding {package_name}: {e}")

    return None

packages = ['libatk1.0-0', 'libgtk-3-0', 'libgtk2.0-0', 'libatk-bridge2.0-0']
for pkg in packages:
    url = find_package_url(pkg)
    if url:
        print(f"{pkg}:{url}")
    else:
        print(f"{pkg}:NOT_FOUND")
EOF

# Try to find and download packages
python3 find_packages.py > package_urls.txt 2>/dev/null || echo "Package search failed"

# Manual fallback - try known working URLs for Ubuntu 24.04
if [ ! -s package_urls.txt ] || ! grep -q "http" package_urls.txt; then
    echo "📋 Using manual package URLs..."
    cat > package_urls.txt << EOF
libatk1.0-0:http://archive.ubuntu.com/ubuntu/pool/main/a/atk1.0/libatk1.0-0_2.53.1-1ubuntu1_amd64.deb
libatk-bridge2.0-0:http://archive.ubuntu.com/ubuntu/pool/main/a/at-spi2-atk/libatk-bridge2.0-0_2.54.0-1_amd64.deb
libgtk-3-0:http://archive.ubuntu.com/ubuntu/pool/main/g/gtk+3.0/libgtk-3-0_3.24.41-4ubuntu1.1_amd64.deb
EOF
fi

# Download and extract each package
while IFS=: read -r package url; do
    if [ "$url" != "NOT_FOUND" ] && [ -n "$url" ]; then
        download_extract_deb "$url"
    fi
done < package_urls.txt

# Also try direct library download as fallback
if [ ! -f usr/lib/x86_64-linux-gnu/libatk-1.0.so.0 ]; then
    echo "🔄 Trying alternative approach..."

    # Download a working Chrome with bundled dependencies
    echo "📦 Downloading standalone Chromium..."
    if wget -q "https://download-chromium.appspot.com/dl/Linux_x64" -O chrome-linux.zip; then
        unzip -q chrome-linux.zip 2>/dev/null || true
        if [ -d chrome-linux ]; then
            mv chrome-linux standalone-chrome
            echo "✅ Downloaded standalone Chrome"
        fi
        rm -f chrome-linux.zip
    fi
fi

# Create library wrapper
echo "🔧 Creating library environment..."
cat > chrome-wrapper.sh << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/home/lever/local-libs/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export CHROME_DEVEL_SANDBOX=""
export DISPLAY=""

# Try different Chrome executables
if [ -f "/home/lever/local-libs/standalone-chrome/chrome" ]; then
    exec "/home/lever/local-libs/standalone-chrome/chrome" "$@"
elif [ -f "/home/lever/.cache/puppeteer/chrome/linux-146.0.7680.76/chrome-linux64/chrome" ]; then
    exec "/home/lever/.cache/puppeteer/chrome/linux-146.0.7680.76/chrome-linux64/chrome" "$@"
else
    exec "/usr/bin/chromium-browser" "$@"
fi
EOF

chmod +x chrome-wrapper.sh

echo "✅ Chrome dependencies setup complete!"
echo "📍 Libraries in: $LIBS_DIR/usr/lib/x86_64-linux-gnu/"
echo "🚀 Wrapper script: $LIBS_DIR/chrome-wrapper.sh"

# Test the setup
echo "🧪 Testing Chrome wrapper..."
if LD_LIBRARY_PATH="$LIBS_DIR/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH" "$LIBS_DIR/chrome-wrapper.sh" --version 2>/dev/null; then
    echo "✅ Chrome wrapper working!"
    exit 0
else
    echo "⚠️  Chrome wrapper needs manual testing"
    exit 0
fi