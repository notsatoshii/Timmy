#!/usr/bin/env python3
"""
Simple OG image generator using basic Python
Creates a 1200x630 image with LEVER branding
"""
import struct
import zlib

def create_png(width, height, data):
    """Create a simple PNG file from RGBA data"""
    def write_chunk(f, chunk_type, data):
        f.write(struct.pack('>I', len(data)))
        f.write(chunk_type)
        f.write(data)
        crc = zlib.crc32(chunk_type + data) & 0xffffffff
        f.write(struct.pack('>I', crc))

    with open('/home/lever/lever-protocol/frontend/user-app/public/lever-og-image.png', 'wb') as f:
        # PNG signature
        f.write(b'\x89PNG\r\n\x1a\n')

        # IHDR chunk
        ihdr = struct.pack('>2I5B', width, height, 8, 2, 0, 0, 0)
        write_chunk(f, b'IHDR', ihdr)

        # IDAT chunk
        compressor = zlib.compressobj()
        png_data = b''
        for y in range(height):
            png_data += b'\x00'  # no filter
            for x in range(width):
                idx = y * width + x
                if idx < len(data):
                    r, g, b = data[idx]
                    png_data += struct.pack('3B', r, g, b)
                else:
                    png_data += b'\x00\x00\x00'

        compressed = compressor.compress(png_data)
        compressed += compressor.flush()
        write_chunk(f, b'IDAT', compressed)

        # IEND chunk
        write_chunk(f, b'IEND', b'')

def create_gradient_with_logo():
    """Create a 1200x630 social media image with gradient and LEVER branding"""
    width, height = 1200, 630
    pixels = []

    # Create a blue gradient background
    for y in range(height):
        for x in range(width):
            # Blue gradient from dark to lighter
            intensity = int(20 + (y / height) * 40)  # Dark blue gradient
            r = min(15, intensity // 3)  # Very dark red
            g = min(25, intensity // 2)  # Slightly more green
            b = min(60 + intensity, 255)  # Blue dominant
            pixels.append((r, g, b))

    # Add some brighter areas to simulate logo placement
    logo_x, logo_y = width // 2, height // 2
    logo_width, logo_height = 400, 80

    # Create a bright rectangular area for the "logo"
    for y in range(max(0, logo_y - logo_height//2), min(height, logo_y + logo_height//2)):
        for x in range(max(0, logo_x - logo_width//2), min(width, logo_x + logo_width//2)):
            idx = y * width + x
            if idx < len(pixels):
                # Bright yellow-green for logo area
                pixels[idx] = (200, 255, 50)

    # Add text-like rectangular blocks
    text_y = logo_y + 60
    for i, text_width in enumerate([300, 500]):  # Two lines of "text"
        text_x = logo_x - text_width // 2
        text_height = 20
        y_offset = i * 35

        for y in range(max(0, text_y + y_offset), min(height, text_y + y_offset + text_height)):
            for x in range(max(0, text_x), min(width, text_x + text_width)):
                idx = y * width + x
                if idx < len(pixels):
                    pixels[idx] = (255, 255, 255)  # White text

    return pixels

# Generate the image
print("Generating social media OG image...")
try:
    pixels = create_gradient_with_logo()
    create_png(1200, 630, pixels)
    print("✅ Successfully created lever-og-image.png (1200x630)")
except Exception as e:
    print(f"❌ Error creating image: {e}")