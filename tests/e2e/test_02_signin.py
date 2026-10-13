"""Signing in: pasting the cookie (default), from the browser, from the environment."""

import json
import os
import stat

import pytest

SESSION = 'e2e-session'
HEADER = 'Cookie: _ga=GA1.2; LEETCODE_SESSION=e2e-session; csrftoken=e2e-csrf; other=1'


def saved_cookies(s):
    path = s.options['leetcode_cookie_file']
    if not os.path.exists(path):
        return None
    return json.load(open(path))


@pytest.fixture
def paste(scenario, lc):
    """A scenario that will answer the sign-in prompt with `answer`."""
    if lc.live:
        pytest.skip('uses fake sessions')
    lc.server.valid_sessions = {SESSION}

    def make(answer, cookie_file=None):
        s = scenario()
        if cookie_file:
            s.let('leetcode_cookie_file', cookie_file)
        s.type_ahead(answer + '\\<CR>')
        return s

    return make


def host(lc):
    return lc.base_url.split('://')[1]


def test_paste_cookie_header(paste, lc):
    s = paste(HEADER)
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert r.vars['logged_in'], r.describe()
    assert 'Signed in.' in r.output
    # Only the cookies the plugin needs are kept, in a file only the user can read.
    assert saved_cookies(s) == {host(lc): {'LEETCODE_SESSION': SESSION, 'csrftoken': 'e2e-csrf'}}
    mode = stat.S_IMODE(os.stat(s.options['leetcode_cookie_file']).st_mode)
    assert mode == 0o600, oct(mode)
    sent = lc.server.requests_to('progress')[-1]['headers']
    assert sent['x-csrftoken'] == 'e2e-csrf'


def test_paste_bare_session_value(paste):
    s = paste(SESSION)
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert r.vars['logged_in'], r.describe()
    assert list(saved_cookies(s).values()) == [{'LEETCODE_SESSION': SESSION}]


def test_paste_rejected_cookie(paste):
    s = paste('LEETCODE_SESSION=wrong; csrftoken=x')
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert not r.vars['logged_in']
    assert 'LeetCode did not accept this cookie' in r.output, r.describe()
    assert saved_cookies(s) is None


def test_paste_without_session_cookie(paste):
    s = paste('csrftoken=x; other=y')
    s.step('LeetCodeSignIn')
    r = s.run()
    r.assert_ok()
    assert 'no LEETCODE_SESSION in the pasted cookie' in r.output, r.describe()


def test_paste_cancelled(paste):
    s = paste('')
    s.step('LeetCodeSignIn')
    r = s.run()
    r.assert_ok()
    assert 'Sign-in cancelled.' in r.output, r.describe()


def test_saved_cookie_is_reused(paste, lc, scenario, tmp_path):
    cookie_file = str(tmp_path / 'cookies.json')
    first = paste(HEADER, cookie_file)
    first.step('LeetCodeSignIn')
    first.run().assert_ok()

    # A later session signs in on its own: no keys are queued, so a prompt
    # would end the test (Vim exits, Neovim times out).
    later = scenario().let('leetcode_cookie_file', cookie_file)
    later.step('LeetCodeList')
    r = later.run()
    r.assert_ok()
    assert 'Two Sum' in r.text(r'^leetcode:///problems/all$'), r.describe()


def test_expired_saved_cookie_asks_again(paste, lc, tmp_path):
    cookie_file = tmp_path / 'cookies.json'
    cookie_file.write_text(json.dumps({host(lc): {'LEETCODE_SESSION': 'expired'}}))
    s = paste(HEADER, str(cookie_file))
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    assert 'saved LeetCode session has expired' in r.output, r.describe()
    assert 'Two Sum' in r.text(r'^leetcode:///problems/all$'), r.describe()
    assert json.loads(cookie_file.read_text())[host(lc)]['LEETCODE_SESSION'] == SESSION


def test_sign_out_forgets_cookie(paste):
    s = paste(HEADER)
    s.step('LeetCodeSignIn')
    s.step('LeetCodeSignOut')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert not r.vars['logged_in']
    assert saved_cookies(s) == {}
    assert 'Signed out.' in r.output


def test_list_prompts_when_not_signed_in(paste):
    s = paste(HEADER)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    assert 'Two Sum' in r.text(r'^leetcode:///problems/all$'), r.describe()


def test_signin_reads_browser_cookie(scenario, lc):
    s = scenario().browser_has(lc.cookies)
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert r.vars['logged_in'], r.describe()
    assert 'Signed in.' in r.output, r.describe()
    progress = lc.server.requests_to('progress')
    assert progress, 'sign-in should verify the session'
    # Both cookies are needed: csrftoken backs the X-CSRFToken header.
    assert 'LEETCODE_SESSION=' in progress[0]['headers'].get('cookie', '')
    assert progress[0]['headers'].get('x-csrftoken') == lc.cookies.get('csrftoken'), r.describe()
    assert progress[0]['headers'].get('user-agent', '').startswith('Mozilla/5.0')


def test_signin_from_environment(scenario, lc, vim_env):
    env = dict(vim_env, LEETCODE_SESSION=lc.cookies['LEETCODE_SESSION'],
               LEETCODE_CSRFTOKEN=lc.cookies.get('csrftoken', ''))
    s = scenario(env=env).let('leetcode_browser', 'env')
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert r.vars['logged_in'], r.describe()
    assert 'Signed in.' in r.output


def test_signin_from_environment_unset(scenario):
    s = scenario().let('leetcode_browser', 'env')
    s.step('LeetCodeSignIn')
    r = s.run()
    r.assert_ok()
    assert '$LEETCODE_SESSION is not set' in r.output, r.describe()


def test_signin_with_expired_cookie(scenario, lc):
    if not lc.live:
        lc.server.override('progress', {'status': 403, 'text': 'Forbidden'})
    s = scenario().browser_has({'LEETCODE_SESSION': 'expired-or-bogus'})
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert 'relogin' in r.output, r.describe()


@pytest.mark.live_only
def test_api_accepts_plugin_requests(lc):
    """Does the progress check pass with the headers the plugin sends today?"""
    import requests
    res = requests.get(lc.base_url + '/api/progress/all/', cookies=lc.cookies,
                       headers={'Referer': lc.base_url, 'X-Requested-With': 'XMLHttpRequest',
                                'X-CSRFToken': lc.cookies.get('csrftoken', '')},
                       timeout=30)
    assert res.status_code == 200, (res.status_code, res.text[:300])
    assert 'solvedTotal' in res.json()
