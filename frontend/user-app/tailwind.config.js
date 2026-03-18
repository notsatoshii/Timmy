/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Surfaces — Void Black base with subtle depth steps
        surface: {
          0: '#000000',   // Void Black (brand)
          1: '#0a0a10',   // card background
          2: '#111118',   // elevated surfaces
          3: '#1a1a24',   // hover states, inputs
        },
        inset: '#000000',
        // Borders
        border: {
          DEFAULT: '#1a1a2a',
          light: '#2a2a3a',
          hover: '#3a3a4a',
          glow: 'rgba(230, 255, 43, 0.15)',
        },
        // Primary: Electric Lime (brand)
        accent: {
          DEFAULT: '#E6FF2B',
          dim: '#C8D926',
          muted: 'rgba(230, 255, 43, 0.15)',
          glow: 'rgba(230, 255, 43, 0.25)',
        },
        // Secondary: Deep Teal (brand)
        teal: {
          DEFAULT: '#0B4650',
          light: '#0E5A66',
          muted: 'rgba(11, 70, 80, 0.3)',
        },
        // Neutral: Steel Gray (brand)
        steel: '#898A8E',
        // Neutral: Soft Ivory (brand)
        ivory: '#F9F7F2',
        // Legacy compatibility
        purple: {
          DEFAULT: '#8060FF',
          dim: '#6B4FD9',
          muted: 'rgba(128, 96, 255, 0.15)',
        },
        // Danger
        danger: {
          DEFAULT: '#FF4868',
          dim: '#D93D58',
          muted: 'rgba(255, 72, 104, 0.15)',
        },
        // Warning
        warning: {
          DEFAULT: '#FFB830',
          dim: '#D99D29',
          muted: 'rgba(255, 184, 48, 0.15)',
        },
        // Long/Short
        long: '#E6FF2B',
        short: '#FF4868',
      },
      fontFamily: {
        sans: ['Inter', 'SF Pro Display', 'system-ui', '-apple-system', 'sans-serif'],
        display: ['Space Grotesk', 'SF Pro Display', 'sans-serif'],
        mono: ['JetBrains Mono', 'SF Mono', 'Consolas', 'monospace'],
      },
      boxShadow: {
        'raised': '0 4px 24px rgba(0,0,0,0.6), 0 1px 2px rgba(0,0,0,0.4)',
        'glow': '0 0 40px rgba(230,255,43,0.05), 0 0 80px rgba(230,255,43,0.02)',
        'glow-strong': '0 0 20px rgba(230,255,43,0.15), 0 0 60px rgba(230,255,43,0.06)',
        'glow-teal': '0 0 30px rgba(11,70,80,0.3), 0 0 60px rgba(11,70,80,0.15)',
        'inset': 'inset 0 2px 8px rgba(0,0,0,0.5)',
        'card': '0 4px 24px rgba(0,0,0,0.6), 0 1px 2px rgba(0,0,0,0.4)',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
