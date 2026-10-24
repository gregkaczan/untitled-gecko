#!/usr/bin/env python3
# Serve docs/art_hunt on http://127.0.0.1:8765 and keep its picks, notes and
# reactions in docs/art_hunt/state.json.
#   GET  /api/state           the whole state
#   POST /api/ops             {"ops": [{"c": collection, "id": doc, "d": data or null}]}
#                             writes only those documents, so two open tabs never undo each other
#   GET  /api/bc-stream?u=... redirects to the current stream of a Bandcamp track page (the
#                             link Bandcamp's own player uses; it expires after about a day)
# Usage: python3 tools/art_hunt_serve.py [port]
import html
import json
import os
import re
import subprocess
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docs', 'art_hunt')
STATE = os.path.join(ROOT, 'state.json')
LOCK = threading.Lock()
STREAMS = {}  # track page url -> (stream url, expiry unix time)


def read_state():
    if not os.path.exists(STATE):
        return {}
    with open(STATE, encoding='utf-8') as f:
        return json.load(f)


def write_state(data):
    tmp = STATE + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    os.replace(tmp, STATE)


def bandcamp_stream(page):
    hit = STREAMS.get(page)
    if hit and hit[1] - 600 > time.time():
        return hit[0]
    # Bandcamp turns Python's own fetcher away; curl gets the page
    body = subprocess.run(['curl', '-sL', '-m', '20', '-A', 'Mozilla/5.0', page],
                          capture_output=True, text=True).stdout
    m = re.search(r'data-tralbum="([^"]+)"', body)
    if not m:
        return None
    info = json.loads(html.unescape(m.group(1)))
    tracks = [t for t in info.get('trackinfo', []) if (t.get('file') or {}).get('mp3-128')]
    if not tracks:
        return None
    url = tracks[0]['file']['mp3-128']
    ts = re.search(r'[?&]ts=(\d+)', url)
    STREAMS[page] = (url, int(ts.group(1)) if ts else time.time() + 3600)
    return url


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path)
        if path.path == '/api/state':
            with LOCK:
                self._json(200, read_state())
        elif path.path == '/api/bc-stream':
            page = parse_qs(path.query).get('u', [''])[0]
            host = urlparse(page).hostname or ''
            if not (host.endswith('.bandcamp.com') and '/track/' in page):
                self._json(400, {'error': 'not a Bandcamp track page'})
                return
            url = bandcamp_stream(page)
            if not url:
                self._json(502, {'error': 'no stream found'})
                return
            self.send_response(302)
            self.send_header('Location', url)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
        else:
            super().do_GET()

    def do_POST(self):
        if urlparse(self.path).path != '/api/ops':
            self._json(404, {})
            return
        try:
            ops = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))['ops']
            assert isinstance(ops, list)
        except (ValueError, KeyError, AssertionError):
            self._json(400, {'error': 'expected {"ops": [...]}'})
            return
        with LOCK:
            state = read_state()
            for op in ops:
                bucket = state.setdefault(op['c'], {})
                if op.get('d') is None:
                    bucket.pop(op['id'], None)
                else:
                    bucket[op['id']] = op['d']
            write_state(state)
        sys.stderr.write(f'saved {len(ops)} change(s)\n')
        self._json(200, {'ok': True})

    def _json(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(('127.0.0.1', port), partial(Handler, directory=ROOT))
    print(f'Art hunt on http://127.0.0.1:{port}/  (state: {os.path.normpath(STATE)})')
    server.serve_forever()
