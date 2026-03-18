/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Neumorphic dark surfaces (layered depth)
        surface: {
          0: '#0f1219',   // page background (warm dark, not pure black)
          1: '#161b26',   // card background
          2: '#1c2233',   // elevated surfaces
          3: '#232a3a',   // hover states, inputs
        },
        // Inset/pressed surfaces
        inset: '#0b0e14',
        // Border colors
        border: {
          DEFAULT: 'rgba(255,255,255,0.04)',
          light: 'rgba(255,255,255,0.07)',
          hover: 'rgba(255,255,255,0.12)',
          glow: 'rgba(0,255,200,0.12)',
        },
        // Primary accent: teal-cyan (LEVER brand)
        accent: {
          DEFAULT: '#00ffc8',
          dim: '#00d4a6',
          muted: 'rgba(0,255,200,0.15)',
          glow: 'rgba(0,255,200,0.25)',
        },
        // Secondary accent (kept for compatibility)
        purple: {
          DEFAULT: '#8060FF',
          dim: '#6B4FD9',
          muted: 'rgba(128, 96, 255, 0.15)',
        },
        // Danger: coral red
        danger: {
          DEFAULT: '#ff3b6a',
          dim: '#d93258',
          muted: 'rgba(255, 59, 106, 0.15)',
        },
        // Warning: amber
        warning: {
          DEFAULT: '#FFB830',
          dim: '#D99D29',
          muted: 'rgba(255, 184, 48, 0.15)',
        },
        // Text hierarchy
        txt: {
          primary: '#e8ecf4',
          secondary: '#6b7a94',
          tertiary: '#3d4a5e',
        },
        // Long/Short
        long: '#00ffc8',
        short: '#ff3b6a',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
        display: ['Space Grotesk', 'Inter', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'Consolas', 'monospace'],
      },
      boxShadow: {
        'raised': '0 4px 24px rgba(0,0,0,0.5), 0 1px 2px rgba(0,0,0,0.3)',
        'glow': '0 0 40px rgba(0,255,200,0.06), 0 0 80px rgba(0,255,200,0.03)',
        'glow-strong': '0 0 20px rgba(0,255,200,0.15), 0 0 60px rgba(0,255,200,0.08)',
        'inset': 'inset 0 2px 8px rgba(0,0,0,0.4)',
        'card': '0 4px 24px rgba(0,0,0,0.5), 0 1px 2px rgba(0,0,0,0.3)',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
