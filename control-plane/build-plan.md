Please run this command to install the missing browser dependencies that are blocking visual verification:

```bash
sudo apt-get update && sudo apt-get install -y libatk-1.0-0 libatk-bridge2.0-0 libgtk-3-0 libgdk-pixbuf2.0-0 libxcomposite1 libxrandr2 libgbm-dev libxss1 libasound2
```

This is critical for the investor demo - without these dependencies, we can't:
- Take screenshots of the UI
- Verify the actual visual quality  
- Confirm that the trading interface works properly
- Document the demo for presentation materials

Once you've installed these, I'll immediately test the visual verification and ensure all 5 tabs (Markets, Trading, Vault, Positions, Portfolio) are working properly for the investor demo.