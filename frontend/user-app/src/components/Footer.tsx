import React from 'react';

const Footer: React.FC = () => {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="bg-surface-1 border-t border-border mt-16">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
          {/* Company Info */}
          <div className="lg:col-span-1">
            <div className="flex items-center space-x-3 mb-4">
              <img
                src="/lever-logo.svg"
                alt="LEVER Protocol"
                className="h-8"
                style={{ filter: 'drop-shadow(0 0 12px rgba(230,255,43,0.2))' }}
              />
              <div>
                <h3 className="lever-heading-md">LEVER Protocol</h3>
                <p className="text-steel/80 text-sm tracking-wide uppercase font-medium">Synthetic Leveraged Perpetuals</p>
                <div className="flex items-center mt-2 space-x-2">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse"></div>
                  <span className="text-xs text-accent font-mono font-medium">Built on Base</span>
                </div>
              </div>
            </div>
            <p className="text-steel text-sm leading-relaxed mb-4">
              Next-generation synthetic leveraged perpetuals on prediction markets.
              Trade binary outcomes with up to 30x leverage, backed by a unified liquidity pool.
            </p>
            <div className="flex space-x-4">
              <a
                href="https://github.com/lever-protocol"
                className="text-steel hover:text-accent transition-colors"
                target="_blank"
                rel="noopener noreferrer"
              >
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 0C5.374 0 0 5.373 0 12c0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23A11.509 11.509 0 0112 5.803c1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576C20.566 21.797 24 17.3 24 12c0-6.627-5.373-12-12-12z"/>
                </svg>
              </a>
              <a
                href="https://twitter.com/leverprotocol"
                className="text-steel hover:text-accent transition-colors"
                target="_blank"
                rel="noopener noreferrer"
              >
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"/>
                </svg>
              </a>
              <a
                href="https://discord.gg/leverprotocol"
                className="text-steel hover:text-accent transition-colors"
                target="_blank"
                rel="noopener noreferrer"
              >
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M20.317 4.492c-1.53-.69-3.17-1.2-4.885-1.49a.075.075 0 00-.079.036c-.21.369-.444.85-.608 1.23a18.566 18.566 0 00-5.487 0 12.36 12.36 0 00-.617-1.23A.077.077 0 008.562 3c-1.714.29-3.354.8-4.885 1.491a.07.07 0 00-.032.027C.533 9.093-.32 13.555.099 17.961a.08.08 0 00.031.055 20.03 20.03 0 005.993 2.98.078.078 0 00.084-.026 13.83 13.83 0 001.226-1.963.074.074 0 00-.041-.104 13.201 13.201 0 01-1.872-.878.075.075 0 01-.008-.125c.126-.093.252-.19.372-.287a.075.075 0 01.078-.01c3.927 1.764 8.18 1.764 12.061 0a.075.075 0 01.079.009c.12.098.246.195.372.288a.075.075 0 01-.006.125c-.598.344-1.22.635-1.873.877a.075.075 0 00-.041.105c.36.687.772 1.341 1.225 1.962a.077.077 0 00.084.028 19.963 19.963 0 006.002-2.981.076.076 0 00.032-.054c.5-5.094-.838-9.52-3.549-13.442a.06.06 0 00-.031-.028zM8.02 15.278c-1.182 0-2.157-1.069-2.157-2.38 0-1.312.956-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.956 2.38-2.157 2.38zm7.975 0c-1.183 0-2.157-1.069-2.157-2.38 0-1.312.955-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.946 2.38-2.157 2.38z"/>
                </svg>
              </a>
            </div>
          </div>

          {/* Product */}
          <div className="lg:col-span-1">
            <h4 className="text-ivory font-display font-semibold text-base mb-4">Product</h4>
            <ul className="space-y-2">
              <li>
                <a href="#markets" className="text-steel hover:text-accent transition-colors text-sm">
                  Prediction Markets
                </a>
              </li>
              <li>
                <a href="#trading" className="text-steel hover:text-accent transition-colors text-sm">
                  Leveraged Trading
                </a>
              </li>
              <li>
                <a href="#vault" className="text-steel hover:text-accent transition-colors text-sm">
                  Liquidity Pool
                </a>
              </li>
              <li>
                <a href="#docs" className="text-steel hover:text-accent transition-colors text-sm">
                  Documentation
                </a>
              </li>
            </ul>
          </div>

          {/* Resources */}
          <div className="lg:col-span-1">
            <h4 className="text-ivory font-display font-semibold text-base mb-4">Resources</h4>
            <ul className="space-y-2">
              <li>
                <a href="#whitepaper" className="text-steel hover:text-accent transition-colors text-sm">
                  Whitepaper
                </a>
              </li>
              <li>
                <a href="#audit" className="text-steel hover:text-accent transition-colors text-sm">
                  Security Audits
                </a>
              </li>
              <li>
                <a href="#blog" className="text-steel hover:text-accent transition-colors text-sm">
                  Blog
                </a>
              </li>
              <li>
                <a href="#support" className="text-steel hover:text-accent transition-colors text-sm">
                  Help Center
                </a>
              </li>
            </ul>
          </div>

          {/* Legal & Compliance */}
          <div className="lg:col-span-1">
            <h4 className="text-ivory font-display font-semibold text-base mb-4">Legal</h4>
            <ul className="space-y-2">
              <li>
                <a href="#terms" className="text-steel hover:text-accent transition-colors text-sm">
                  Terms of Service
                </a>
              </li>
              <li>
                <a href="#privacy" className="text-steel hover:text-accent transition-colors text-sm">
                  Privacy Policy
                </a>
              </li>
              <li>
                <a href="#risks" className="text-steel hover:text-accent transition-colors text-sm">
                  Risk Disclaimer
                </a>
              </li>
              <li>
                <a href="#compliance" className="text-steel hover:text-accent transition-colors text-sm">
                  Compliance
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Risk Disclaimer */}
        <div className="border-t border-border pt-8 mt-8">
          <div className="bg-warning-muted border border-warning/20 rounded-lg p-4 mb-6">
            <div className="flex">
              <div className="flex-shrink-0">
                <svg className="h-5 w-5 text-warning" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="ml-3">
                <h5 className="text-warning font-semibold text-sm mb-2">Risk Disclaimer</h5>
                <p className="text-steel text-sm leading-relaxed">
                  LEVER Protocol involves significant financial risks. Leveraged trading can result in substantial losses exceeding your initial investment.
                  Only trade with funds you can afford to lose. This platform is experimental and may contain bugs or vulnerabilities.
                  Past performance does not guarantee future results. Please read our full risk disclosure before using any services.
                </p>
              </div>
            </div>
          </div>

          {/* Bottom bar */}
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center space-x-4">
              <p className="text-steel text-sm">
                © {currentYear} LEVER Protocol. All rights reserved.
              </p>
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-accent rounded-full animate-pulse"></div>
                <span className="text-steel text-xs">
                  Built on <span className="text-accent font-mono">Base</span>
                </span>
              </div>
            </div>

            <div className="mt-4 sm:mt-0 flex items-center space-x-4 text-xs text-steel">
              <span>Version 1.0.0-beta</span>
              <span>•</span>
              <span>Testnet</span>
              <span>•</span>
              <span className="flex items-center space-x-1">
                <div className="w-1.5 h-1.5 bg-long rounded-full"></div>
                <span>Operational</span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;