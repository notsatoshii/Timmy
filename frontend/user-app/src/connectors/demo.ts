// Demo wallet utilities
export const TEST_WALLET_KEY = 'bf4b6a6e7c99d538edf38d0ac535a44729bb8c9907de5bb9494d852eb4e812ec'
export const DEMO_ADDRESS = '0xB072263740D7c60f1Aa0BF46e737F83544C7b785' as `0x${string}`

export const isDemoMode = () => localStorage.getItem('demo-mode') === 'true'
export const setDemoMode = (enabled: boolean) => {
  if (enabled) {
    localStorage.setItem('demo-mode', 'true')
  } else {
    localStorage.removeItem('demo-mode')
  }
}