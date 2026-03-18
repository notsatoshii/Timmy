#!/usr/bin/env node
/**
 * Secure SPA Server for LEVER Protocol Frontend
 *
 * Addresses security and monitoring requirements:
 * - Proper 404 responses for missing static resources
 * - Security headers (HSTS, X-Frame-Options, etc.)
 * - Health endpoint for monitoring
 * - Security monitoring for vulnerability scan detection
 * - React SPA routing support
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

class SecureSPAServer {
    constructor(options = {}) {
        this.port = options.port || 3000;
        this.buildDir = options.buildDir || '/home/lever/lever-protocol/frontend/user-app/build';
        this.logFile = options.logFile || '/home/lever/lever-protocol/control-plane/dispatcher-logs/security-access.log';

        // Security monitoring patterns for vulnerability scanning
        this.suspiciousPatterns = [
            /\.env/i,
            /\.php$/i,
            /\.bak$/i,
            /backup/i,
            /config\.php/i,
            /wp-admin/i,
            /admin\.php/i,
            /phpinfo\.php/i,
            /shell\.php/i,
            /upload\.php/i,
            /sql/i,
            /mysql/i,
            /database/i,
            /\.git/i,
            /robots\.txt/i,
            /sitemap\.xml/i
        ];

        // Cache for static files to improve performance
        this.cache = new Map();
        this.cacheTimeout = 5 * 60 * 1000; // 5 minutes

        this.server = null;
    }

    /**
     * Get security headers for all responses
     */
    getSecurityHeaders() {
        return {
            'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': 'DENY',
            'X-XSS-Protection': '1; mode=block',
            'Referrer-Policy': 'strict-origin-when-cross-origin',
            'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
            'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https: wss: ws:; frame-ancestors 'none';"
        };
    }

    /**
     * Log security events and potential vulnerability scanning
     */
    logSecurityEvent(req, eventType, details = '') {
        const timestamp = new Date().toISOString();
        const clientIP = req.headers['x-forwarded-for'] || req.socket?.remoteAddress || req.connection?.remoteAddress || 'unknown';
        const userAgent = req.headers['user-agent'] || 'unknown';
        const referer = req.headers['referer'] || 'none';

        const logEntry = {
            timestamp,
            event_type: eventType,
            client_ip: clientIP,
            method: req.method,
            url: req.url,
            user_agent: userAgent,
            referer: referer,
            details: details
        };

        const logLine = JSON.stringify(logEntry) + '\n';

        try {
            fs.appendFileSync(this.logFile, logLine);
        } catch (error) {
            console.error('Failed to write security log:', error.message);
        }

        // Also log to console for immediate visibility
        if (eventType === 'vulnerability_scan' || eventType === 'suspicious_request') {
            console.warn(`🚨 SECURITY: ${eventType} from ${clientIP} - ${req.url}`);
        }
    }

    /**
     * Check if request path matches vulnerability scanning patterns
     */
    isSuspiciousRequest(pathname) {
        return this.suspiciousPatterns.some(pattern => pattern.test(pathname));
    }

    /**
     * Get MIME type for file extension
     */
    getMimeType(ext) {
        const mimeTypes = {
            '.html': 'text/html',
            '.js': 'text/javascript',
            '.css': 'text/css',
            '.json': 'application/json',
            '.png': 'image/png',
            '.jpg': 'image/jpeg',
            '.gif': 'image/gif',
            '.ico': 'image/x-icon',
            '.svg': 'image/svg+xml',
            '.woff': 'font/woff',
            '.woff2': 'font/woff2',
            '.ttf': 'font/ttf',
            '.eot': 'font/eot'
        };
        return mimeTypes[ext] || 'application/octet-stream';
    }

    /**
     * Serve static file with proper caching and security headers
     */
    serveStaticFile(filePath, res) {
        const ext = path.extname(filePath).toLowerCase();
        const mimeType = this.getMimeType(ext);

        // Check cache first
        const cacheKey = filePath;
        const cached = this.cache.get(cacheKey);
        if (cached && Date.now() - cached.timestamp < this.cacheTimeout) {
            res.writeHead(200, {
                'Content-Type': mimeType,
                'Cache-Control': 'public, max-age=300', // 5 minutes cache
                ...this.getSecurityHeaders()
            });
            res.end(cached.content);
            return;
        }

        try {
            const content = fs.readFileSync(filePath);

            // Cache the content
            this.cache.set(cacheKey, {
                content,
                timestamp: Date.now()
            });

            res.writeHead(200, {
                'Content-Type': mimeType,
                'Cache-Control': 'public, max-age=300',
                ...this.getSecurityHeaders()
            });
            res.end(content);
        } catch (error) {
            res.writeHead(404, {
                'Content-Type': 'application/json',
                ...this.getSecurityHeaders()
            });
            res.end(JSON.stringify({ error: 'File not found' }));
        }
    }

    /**
     * Serve the React SPA index.html for routes
     */
    serveSPARoute(res) {
        const indexPath = path.join(this.buildDir, 'index.html');

        try {
            const html = fs.readFileSync(indexPath, 'utf8');
            res.writeHead(200, {
                'Content-Type': 'text/html',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                ...this.getSecurityHeaders()
            });
            res.end(html);
        } catch (error) {
            res.writeHead(500, {
                'Content-Type': 'application/json',
                ...this.getSecurityHeaders()
            });
            res.end(JSON.stringify({ error: 'Internal server error' }));
        }
    }

    /**
     * Handle health endpoint for monitoring
     */
    handleHealthCheck(res) {
        const health = {
            status: 'healthy',
            timestamp: new Date().toISOString(),
            service: 'lever-frontend',
            port: this.port,
            uptime: process.uptime(),
            memory: process.memoryUsage(),
            version: require('/home/lever/lever-protocol/frontend/user-app/package.json').version
        };

        res.writeHead(200, {
            'Content-Type': 'application/json',
            ...this.getSecurityHeaders()
        });
        res.end(JSON.stringify(health, null, 2));
    }

    /**
     * Main request handler
     */
    handleRequest(req, res) {
        const parsedUrl = url.parse(req.url, true);
        const pathname = parsedUrl.pathname;

        // Log all requests for security monitoring
        this.logSecurityEvent(req, 'http_request');

        // Check for suspicious/vulnerability scanning requests
        if (this.isSuspiciousRequest(pathname)) {
            this.logSecurityEvent(req, 'vulnerability_scan', `Suspicious path: ${pathname}`);

            // Return 404 for suspicious requests (don't reveal what exists)
            res.writeHead(404, {
                'Content-Type': 'application/json',
                ...this.getSecurityHeaders()
            });
            res.end(JSON.stringify({ error: 'Not found' }));
            return;
        }

        // Handle health endpoint
        if (pathname === '/health' || pathname === '/api/health') {
            this.handleHealthCheck(res);
            return;
        }

        // Clean the pathname
        const cleanPath = pathname === '/' ? '/index.html' : pathname;
        const filePath = path.join(this.buildDir, cleanPath);

        // Security: Prevent directory traversal
        if (!filePath.startsWith(this.buildDir)) {
            this.logSecurityEvent(req, 'directory_traversal_attempt', `Blocked path: ${pathname}`);
            res.writeHead(403, {
                'Content-Type': 'application/json',
                ...this.getSecurityHeaders()
            });
            res.end(JSON.stringify({ error: 'Forbidden' }));
            return;
        }

        // Check if it's a request for a static file
        if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
            this.serveStaticFile(filePath, res);
            return;
        }

        // Check if it's a request for a known static asset pattern that should 404
        const isAssetRequest = /\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|json|map)$/i.test(pathname);
        if (isAssetRequest) {
            this.logSecurityEvent(req, 'missing_asset', `Asset not found: ${pathname}`);
            res.writeHead(404, {
                'Content-Type': 'application/json',
                ...this.getSecurityHeaders()
            });
            res.end(JSON.stringify({ error: 'Asset not found' }));
            return;
        }

        // Serve SPA route (fallback to index.html for client-side routing)
        this.serveSPARoute(res);
    }

    /**
     * Start the server
     */
    start() {
        // Ensure log directory exists
        const logDir = path.dirname(this.logFile);
        if (!fs.existsSync(logDir)) {
            fs.mkdirSync(logDir, { recursive: true });
        }

        // Verify build directory exists
        if (!fs.existsSync(this.buildDir)) {
            throw new Error(`Build directory not found: ${this.buildDir}`);
        }

        // Verify index.html exists
        const indexPath = path.join(this.buildDir, 'index.html');
        if (!fs.existsSync(indexPath)) {
            throw new Error(`index.html not found: ${indexPath}`);
        }

        this.server = http.createServer((req, res) => {
            this.handleRequest(req, res);
        });

        this.server.listen(this.port, () => {
            console.log(`🚀 Secure SPA Server running on port ${this.port}`);
            console.log(`📁 Serving from: ${this.buildDir}`);
            console.log(`📊 Health endpoint: http://localhost:${this.port}/health`);
            console.log(`🔒 Security logging to: ${this.logFile}`);

            // Log server startup
            this.logSecurityEvent({ url: '/startup', headers: {}, method: 'SERVER' }, 'server_start', `Port: ${this.port}`);
        });

        // Graceful shutdown handling
        process.on('SIGTERM', () => this.stop());
        process.on('SIGINT', () => this.stop());

        return this.server;
    }

    /**
     * Stop the server
     */
    stop() {
        if (this.server) {
            console.log('🛑 Shutting down Secure SPA Server...');
            this.logSecurityEvent({ url: '/shutdown', headers: {}, method: 'SERVER' }, 'server_stop');
            this.server.close(() => {
                console.log('✅ Server stopped');
                process.exit(0);
            });
        }
    }
}

// CLI interface
if (require.main === module) {
    const port = process.env.PORT || process.argv[2] || 3000;
    const buildDir = process.env.BUILD_DIR || process.argv[3] || '/home/lever/lever-protocol/frontend/user-app/build';

    const server = new SecureSPAServer({
        port: parseInt(port),
        buildDir
    });

    try {
        server.start();
    } catch (error) {
        console.error('❌ Failed to start server:', error.message);
        process.exit(1);
    }
}

module.exports = SecureSPAServer;