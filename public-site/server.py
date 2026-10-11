#!/usr/bin/env python3
"""Local-only preview server for the Eazy static site.

It serves assets normally and falls back to index.html for the declared page
routes. It does not deploy, mutate DNS, or contact production services.
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent
ROUTES = {
    '/', '/privacy', '/terms', '/cookies', '/support', '/delete-account',
    '/community-guidelines', '/payments-refunds', '/security'
}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        path = self.path.split('?', 1)[0].rstrip('/') or '/'
        if path in ROUTES:
            self.path = '/index.html'
        super().do_GET()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', '4173'))
    server = ThreadingHTTPServer(('0.0.0.0', port), Handler)
    print(f'Eazy public-site preview listening on http://0.0.0.0:{port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
