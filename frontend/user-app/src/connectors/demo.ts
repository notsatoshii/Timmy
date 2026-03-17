// Demo wallet utilities
export const TEST_WALLET_KEY = 'e7d9967576ecd9bc2d3d6003e6565261b0bc3d75f20535efc1e8267ec364feb5'
export const DEMO_ADDRESS = '0xafB383Af9352B669a5e9755Ec5D0A253dbd034Da' as `0x${string}`

export const isDemoMode = () => localStorage.getItem('demo-mode') === 'true'
export const setDemoMode = (enabled: boolean) => {
  if (enabled) {
    localStorage.setItem('demo-mode', 'true')
  } else {
    localStorage.removeItem('demo-mode')
  }
}