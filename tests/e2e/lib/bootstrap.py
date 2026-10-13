# Runs inside Vim (via :py3file) before the plugin is loaded.
#
# It points the plugin at the test server and, depending on the scenario,
# installs stand-ins for browser_cookie3/keyring or injects a signed-in
# session directly. Vim globals g:e2e_config (path to a JSON file) and
# g:e2e_vars (result dict) are provided by the scenario script.

import json
import os
import sys
import types

import vim


def _bootstrap():
    with open(vim.eval('g:e2e_config'), encoding='utf-8') as f:
        cfg = json.load(f)

    if cfg.get('browser_cookies') is not None:
        _install_cookie_stubs(cfg)

    if not cfg.get('preimport', True):
        # Let the plugin import leetcode.py itself, exactly as it would for a
        # user. The base URL then comes from g:leetcode_china.
        return

    # The plugin only sets LEETCODE_BASE_URL and appends these paths before
    # `import leetcode`. Doing the same here first means its own `import`
    # reuses this module, which talks to the URL under test.
    os.environ['LEETCODE_BASE_URL'] = cfg['base_url']
    for p in (cfg['autoload_dir'], os.path.join(cfg['autoload_dir'], 'thirdparty')):
        if p not in sys.path:
            sys.path.append(p)
    import leetcode  # raises here if dependencies are broken
    # Bind it in Vim's Python globals, where the plugin's own import puts it.
    globals()['leetcode'] = leetcode

    if cfg.get('session_cookies'):
        import requests
        leetcode.session = requests.Session()
        for name, value in cfg['session_cookies'].items():
            leetcode.session.cookies.set(name, value)


def _install_cookie_stubs(cfg):
    """Fake browser_cookie3 and keyring so the real sign-in code path runs."""
    from http.cookiejar import Cookie, CookieJar
    from urllib.parse import urlsplit

    host = urlsplit(cfg['base_url']).hostname

    def jar(domain_name=None, **kwargs):
        j = CookieJar()
        for name, value in cfg['browser_cookies'].items():
            j.set_cookie(Cookie(0, name, value, None, False, host, True, False,
                                '/', True, False, None, False, None, None, {}))
        return j

    bc3 = types.ModuleType('browser_cookie3')
    for browser in ('chrome', 'firefox', 'chromium', 'brave', 'edge', 'load'):
        setattr(bc3, browser, jar)

    store = {}
    kr = types.ModuleType('keyring')
    kr.get_password = lambda service, user: store.get((service, user))
    kr.set_password = lambda service, user, pw: store.__setitem__((service, user), pw)
    kr.delete_password = lambda service, user: store.pop((service, user), None)
    kr._store = store

    sys.modules['browser_cookie3'] = bc3
    sys.modules['keyring'] = kr


try:
    _bootstrap()
except BaseException as e:  # report, don't abort: the test decides
    vim.command('let g:e2e_vars.bootstrap_error = {}'.format(
        json.dumps('{}: {}'.format(type(e).__name__, e))))
