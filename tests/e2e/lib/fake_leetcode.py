"""A local stand-in for leetcode.com that the plugin can be pointed at.

The server has two modes:

* replay: answer every request from JSON fixtures on disk. Tests can override
  individual routes to simulate failures.
* proxy: forward every request to a real upstream (https://leetcode.com) and
  optionally record the responses as fixtures, so a replay run can later
  reproduce exactly what the live site returned.

Every request the plugin makes is logged in `server.requests`, so tests can
assert on what was sent (paths, headers, bodies) as well as what came back.
"""

import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

# (method, path regex, route name). The route name is the fixture file name.
# The first named group (or the GraphQL slug variable) is the fixture "key":
# a fixture named `<route>@<key>.json` wins over `<route>.json`.
ROUTES = [
    ('GET', r'^/api/problems/(?P<category>[^/]+)/?$', 'problems'),
    ('GET', r'^/api/progress/all/?$', 'progress'),
    ('POST', r'^/graphql/?$', 'graphql'),
    ('GET', r'^/graphql/?$', 'csrf_page'),
    ('POST', r'^/problems/(?P<slug>[^/]+)/interpret_solution/?$', 'interpret_solution'),
    ('POST', r'^/problems/(?P<slug>[^/]+)/submit/?$', 'submit'),
    ('GET', r'^/submissions/detail/(?P<id>[^/]+)/check/?$', 'check'),
    ('GET', r'^/api/submissions/(?P<slug>[^/]+)/?$', 'submissions'),
]

# Routes that answer 403 in replay mode unless a session cookie is sent, so
# sign-in bugs that drop the cookie are caught.
REQUIRES_LOGIN = {'progress'}

# Like LeetCode, replay mode answers 499 to these without a current CSRF
# token (the csrftoken cookie, repeated in X-CSRFToken). GET /graphql/
# hands one out.
REQUIRES_CSRF = {'interpret_solution', 'submit'}

# Headers that must not be copied between the plugin and the upstream.
HOP_HEADERS = {'host', 'connection', 'content-length', 'transfer-encoding',
               'content-encoding', 'keep-alive', 'accept-encoding'}


def _match_route(method, path):
    for route_method, pattern, name in ROUTES:
        if route_method != method:
            continue
        m = re.match(pattern, path)
        if m:
            key = next(iter(m.groupdict().values()), None)
            return name, key
    return None, None


def _graphql_route(body):
    """Split /graphql into one route per operation, keyed by the slug or submission id."""
    try:
        payload = json.loads(body or b'{}')
    except ValueError:
        return 'graphql', None
    op = payload.get('operationName')
    if not op:
        m = re.search(r'\b(?:query|mutation)\s+(\w+)', payload.get('query', ''))
        op = m.group(1) if m else 'anonymous'
    variables = payload.get('variables') or {}
    key = variables.get('titleSlug') or variables.get('slug') or variables.get('submissionId')
    key = None if key is None else str(key)
    return 'graphql.' + op, key


class FakeLeetCode:
    def __init__(self, fixture_dirs, upstream=None, record_dir=None):
        self.fixture_dirs = [Path(d) for d in fixture_dirs]
        self.upstream = upstream.rstrip('/') if upstream else None
        self.record_dir = Path(record_dir) if record_dir else None
        self.requests = []
        # When set, only these LEETCODE_SESSION values count as signed in.
        self.valid_sessions = None
        # The CSRF tokens GET /graphql/ hands out, in turn (the last one
        # repeats), and those still accepted.
        self.csrf_tokens = ['e2e-csrf']
        self.valid_csrf_tokens = {'e2e-csrf'}
        self._overrides = {}
        self._sequences = {}
        self._lock = threading.Lock()
        self._httpd = None
        self._thread = None

    # ---- lifecycle -------------------------------------------------------

    def start(self):
        server = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                server._handle(self)

            def do_POST(self):
                server._handle(self)

            def log_message(self, *args):
                pass

        self._httpd = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        if self._httpd:
            self._httpd.shutdown()
            self._httpd.server_close()

    @property
    def base_url(self):
        host, port = self._httpd.server_address
        return 'http://{}:{}'.format(host, port)

    # ---- test API --------------------------------------------------------

    def override(self, route, response, key=None):
        """Answer `route` (optionally only for `key`) with `response`.

        `response` uses the fixture format: {"status": 200, "json": ...},
        {"status": 200, "text": ...}, or a list of those to play in order.
        """
        with self._lock:
            self._overrides[(route, key)] = response
            self._sequences.pop((route, key), None)

    def requests_to(self, route):
        return [r for r in self.requests if r['route'] == route]

    # ---- request handling ------------------------------------------------

    def _handle(self, h):
        path = urlsplit(h.path).path
        length = int(h.headers.get('Content-Length') or 0)
        body = h.rfile.read(length) if length else b''

        route, key = _match_route(h.command, path)
        if route == 'graphql':
            route, key = _graphql_route(body)
        record = {
            'method': h.command,
            'path': h.path,
            'route': route,
            'key': key,
            'headers': {k.lower(): v for k, v in h.headers.items()},
            'body': body.decode('utf-8', 'replace'),
        }

        if self.upstream and not self._has_override(route, key):
            status, headers, payload, ok = self._forward(h, body)
            if ok and self.record_dir and route:
                self._record(route, key, status, headers, payload)
        elif (route in REQUIRES_LOGIN and not self._has_override(route, key)
              and not self._signed_in(record['headers'].get('cookie', ''))):
            status, headers, payload = 403, {'Content-Type': 'text/plain'}, b'not signed in'
        elif route == 'csrf_page' and not self._has_override(route, key):
            status, headers, payload = 200, {
                'Content-Type': 'application/json',
                'Set-Cookie': 'csrftoken={}; Max-Age=31449600; Path=/; SameSite=Lax'.format(
                    self._next_csrf_token())}, b'{}'
        elif route in REQUIRES_CSRF and not self._csrf_ok(record['headers']):
            status, headers, payload = 499, {'Content-Type': 'text/plain'}, b''
        else:
            status, headers, payload = self._replay(route, key)

        record['status'] = status
        with self._lock:
            self.requests.append(record)

        h.send_response(status)
        for k, v in headers.items():
            h.send_header(k, v)
        h.send_header('Content-Length', str(len(payload)))
        h.end_headers()
        h.wfile.write(payload)

    def _next_csrf_token(self):
        with self._lock:
            return self.csrf_tokens.pop(0) if len(self.csrf_tokens) > 1 else self.csrf_tokens[0]

    def _csrf_ok(self, headers):
        cookies = dict(c.strip().split('=', 1)
                       for c in headers.get('cookie', '').split(';') if '=' in c)
        token = headers.get('x-csrftoken', '')
        return token == cookies.get('csrftoken') and token in self.valid_csrf_tokens

    def _signed_in(self, cookie_header):
        cookies = dict(c.strip().split('=', 1) for c in cookie_header.split(';') if '=' in c)
        session = cookies.get('LEETCODE_SESSION')
        if self.valid_sessions is None:
            return bool(session)
        return session in self.valid_sessions

    def _has_override(self, route, key):
        return (route, key) in self._overrides or (route, None) in self._overrides

    def _lookup(self, route, key):
        if route is None:
            return None
        for k in ((route, key), (route, None)):
            if k in self._overrides:
                return k, self._overrides[k]
        names = (['{}@{}.json'.format(route, key)] if key else []) + [route + '.json']
        for d in self.fixture_dirs:
            for name in names:
                p = d / name
                if p.exists():
                    return (route, key, str(p)), json.loads(p.read_text('utf-8'))
        return None

    def _replay(self, route, key):
        found = self._lookup(route, key)
        if not found:
            return 404, {'Content-Type': 'text/plain'}, (
                'fake leetcode: no fixture for route={} key={}'.format(route, key)).encode()
        seq_key, response = found
        if isinstance(response, list):
            # Play a list of responses in order; the last one repeats.
            with self._lock:
                i = self._sequences.get(seq_key, 0)
                self._sequences[seq_key] = i + 1
            response = response[min(i, len(response) - 1)]
        status = response.get('status', 200)
        if 'json' in response:
            return status, {'Content-Type': 'application/json'}, \
                json.dumps(response['json']).encode('utf-8')
        ctype = response.get('content_type', 'text/html; charset=utf-8')
        return status, {'Content-Type': ctype}, response.get('text', '').encode('utf-8')

    def _forward(self, h, body):
        import requests  # only needed in proxy mode

        upstream_host = urlsplit(self.upstream).netloc
        headers = {k: v for k, v in h.headers.items() if k.lower() not in HOP_HEADERS}
        # The plugin thinks it talks to us; make Origin/Referer point upstream.
        for name in ('Origin', 'Referer'):
            if name in headers:
                headers[name] = headers[name].replace(self.base_url, self.upstream)
        headers['Host'] = upstream_host
        try:
            res = requests.request(h.command, self.upstream + h.path, headers=headers,
                                   data=body or None, allow_redirects=False, timeout=30)
        except requests.RequestException as e:
            return 502, {'Content-Type': 'text/plain'}, \
                'fake leetcode proxy error: {}'.format(e).encode(), False
        out_headers = {k: v for k, v in res.headers.items()
                       if k.lower() not in HOP_HEADERS and k.lower() != 'set-cookie'}
        # Account cookies stay out, but the plugin fetches its CSRF token.
        token = res.cookies.get('csrftoken')
        if token:
            out_headers['Set-Cookie'] = 'csrftoken={}; Path=/'.format(token)
        return res.status_code, out_headers, res.content, True

    def _record(self, route, key, status, headers, payload):
        self.record_dir.mkdir(parents=True, exist_ok=True)
        name = '{}@{}.json'.format(route, key) if key else route + '.json'
        text = payload.decode('utf-8', 'replace')
        if 'json' in headers.get('Content-Type', ''):
            try:
                entry = {'status': status, 'json': json.loads(text)}
            except ValueError:
                entry = {'status': status, 'text': text}
        else:
            entry = {'status': status, 'text': text,
                     'content_type': headers.get('Content-Type', 'text/html')}
        path = self.record_dir / name
        with self._lock:
            if route == 'check':
                # Polling endpoint: keep the whole sequence.
                existing = json.loads(path.read_text('utf-8')) if path.exists() else []
                existing.append(entry)
                entry = existing
            path.write_text(json.dumps(entry, indent=2, ensure_ascii=False) + '\n', 'utf-8')
