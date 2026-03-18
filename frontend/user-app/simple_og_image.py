#!/usr/bin/env python3
"""
Very simple PNG creator for OG image
"""
import struct
import zlib

def create_simple_png():
    width, height = 1200, 630

    # Create simple RGB data (3 bytes per pixel)
    pixels = bytearray()

    for y in range(height):
        pixels.append(0)  # Filter type: None
        for x in range(width):
            # Create a simple gradient background
            if y < height // 3:
                # Dark blue top
                pixels.extend([15, 31, 89])
            elif y < 2 * height // 3:
                # Purple middle with logo area
                if (width//3 <= x <= 2*width//3) and (height//3 <= y <= 2*height//3):
                    # Bright area for logo
                    pixels.extend([200, 255, 0])  # Bright yellow-green
                else:
                    pixels.extend([45, 55, 120])  # Purple
            else:
                # Darker blue bottom
                pixels.extend([25, 40, 100])

    # Compress the pixel data
    compressor = zlib.compressobj()
    compressed = compressor.compress(pixels)
    compressed += compressor.flush()

    # Write PNG file
    with open('/home/lever/lever-protocol/frontend/user-app/public/lever-og-image.png', 'wb') as f:
        # PNG signature
        f.write(b'\x89PNG\r\n\x1a\n')

        # IHDR chunk
        ihdr = struct.pack('>2I5B', width, height, 8, 2, 0, 0, 0)  # RGB, 8-bit
        f.write(struct.pack('>I', len(ihdr)))
        f.write(b'IHDR')
        f.write(ihdr)
        crc = zlib.crc32(b'IHDR' + ihdr) & 0xffffffff
        f.write(struct.pack('>I', crc))

        # IDAT chunk
        f.write(struct.pack('>I', len(compressed)))
        f.write(b'IDAT')
        f.write(compressed)
        crc = zlib.crc32(b'IDAT' + compressed) & 0xffffffff
        f.write(struct.pack('>I', crc))

        # IEND chunk
        f.write(struct.pack('>I', 0))
        f.write(b'IEND')
        crc = zlib.crc32(b'IEND') & 0xffffffff
        f.write(struct.pack('>I', crc))

try:
    create_simple_png()
    print("✅ Created simple OG image")
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()