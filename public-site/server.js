const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = __dirname;
const port = Number(process.env.PORT || 3000);
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function renderPage(pathname) {
  const template = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const app = { innerHTML: '' };
  const nav = { classList: { toggle: () => false } };
  const menu = { addEventListener: () => {}, setAttribute: () => {} };
  const document = {
    title: 'Eazy',
    querySelector(selector) {
      if (selector === '#app') return app;
      if (selector === '#site-nav') return nav;
      if (selector === '.menu-toggle') return menu;
      return null;
    },
  };
  const window = {
    location: { pathname },
    addEventListener: () => {},
  };
  const script = fs.readFileSync(path.join(root, 'site.js'), 'utf8');
  vm.runInNewContext(script, { window, document, String, Object, Array, RegExp }, { timeout: 1000 });
  const rendered = template.replace('<main id="app" tabindex="-1"></main>', '<main id="app" tabindex="-1">' + app.innerHTML + '</main>')
    .replace('<title>Eazy | Your world, made easier</title>', '<title>' + escapeHtml(document.title) + '</title>');
  return rendered;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[char]);
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8', Allow: 'GET, HEAD' });
    return res.end('Method not allowed');
  }
  const pathname = new URL(req.url || '/', 'http://localhost').pathname;
  if (pathname === '/health' || pathname === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    return res.end(req.method === 'HEAD' ? undefined : JSON.stringify({ status: 'ok', service: 'eazy-public-site' }));
  }

  let requested;
  try { requested = decodeURIComponent(pathname); } catch {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Bad request');
  }

  if (requested === '/' || requested.endsWith('/')) {
    const pagePath = requested === '/' ? '/' : requested;
    try {
      const html = renderPage(pagePath);
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=60',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
        'X-Frame-Options': 'DENY',
        'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      });
      return res.end(req.method === 'HEAD' ? undefined : html);
    } catch (error) {
      console.error('Page render failed:', error);
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Page temporarily unavailable');
    }
  }

  const resolved = path.resolve(root, '.' + requested);
  if (!resolved.startsWith(root + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Forbidden');
  }
  fs.stat(resolved, (statError, stat) => {
    if (statError || !stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Not found');
    }
    res.writeHead(200, {
      'Content-Type': contentTypes[path.extname(resolved)] || 'application/octet-stream',
      'Cache-Control': /\.(css|js|svg|png|ico)$/.test(resolved) ? 'public, max-age=300' : 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'X-Frame-Options': 'DENY',
    });
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(resolved).pipe(res);
  });
});

server.listen(port, '0.0.0.0', () => console.log('Eazy public site listening on ' + port));
