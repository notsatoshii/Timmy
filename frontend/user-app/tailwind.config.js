/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Core backgrounds (deep navy → pitch black)
        surface: {
          0: '#050509',   // page background
          1: '#0B0B14',   // card background
          2: '#111120',   // elevated surfaces
          3: '#1A1A2E',   // hover states, inputs
        },
        // Border colors
        border: {
          DEFAULT: '#1E1E3A',
          light: '#2A2A4A',
          hover: '#3A3A5A',
        },
        // Accent: electric green
        accent: {
          DEFAULT: '#E6FF2B',
          dim: '#C8D926',
          muted: 'rgba(0, 232, 180, 0.15)',
          glow: 'rgba(0, 232, 180, 0.25)',
        },
        // Secondary: purple
        purple: {
          DEFAULT: '#8060FF',
          dim: '#6B4FD9',
          muted: 'rgba(128, 96, 255, 0.15)',
        },
        // Danger: coral red
        danger: {
          DEFAULT: '#FF4868',
          dim: '#D93D58',
          muted: 'rgba(255, 72, 104, 0.15)',
        },
        // Warning: amber
        warning: {
          DEFAULT: '#FFB830',
          dim: '#D99D29',
          muted: 'rgba(255, 184, 48, 0.15)',
        },
        // Long/Short (reuse accent/danger)
        long: '#E6FF2B',
        short: '#FF4868',
      },
      fontFamily: {
        sans: ['Inter', 'Instrument Sans', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'Consolas', 'monospace'],
      },
      boxShadow: {
        'glow-green': '0 0 20px rgba(0, 232, 180, 0.15)',
        'glow-purple': '0 0 20px rgba(128, 96, 255, 0.15)',
        'card': '0 1px 3px rgba(0, 0, 0, 0.3)',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
