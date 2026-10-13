"""Signing in through the browser-cookie path (browser_cookie3 + keyring)."""

import pytest


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


def test_signin_without_browser_configured(scenario):
    s = scenario()
    s.step('LeetCodeSignIn')
    s.capture('logged_in', "py3eval('bool(leetcode.is_login())')")
    r = s.run()
    r.assert_ok()
    assert not r.vars['logged_in']
    assert 'g:leetcode_browser is disabled' in r.output, r.describe()


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
