"""g:leetcode_backend = 'vim': the whole workflow without Python packages."""

import pytest

pytestmark = pytest.mark.replay_only


@pytest.mark.vim_only
def test_full_workflow_without_python(scenario, lc, bare_vim_env):
    lc.server.valid_sessions = {'e2e-session'}
    s = scenario(env=bare_vim_env)
    # Sign in by pasting, list, open, run, submit, look at a submission.
    s.type_ahead(r'Cookie: LEETCODE_SESSION=e2e-session; csrftoken=e2e-csrf\<CR>')
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press(r'\<CR>')
    s.capture('desc', "getbufline(bufnr('^\\[DESCRIPTION\\]'), 1, '$')")
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(r'^leetcode:///result$')
    s.capture('test_result', "getbufline(bufnr('leetcode:///result'), 1, '$')")
    s.step('LeetCodeSubmit')
    s.wait_for('!leetcode#Busy()')
    s.capture('submit_result', "getbufline(bufnr('leetcode:///result'), 1, '$')")
    s.step('only')
    s.step('hide buffer leetcode:///problems/all')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^| 123456 ')
    s.press(r'\<CR>')
    s.capture('python_used', "has('python3') ? py3eval('\"leetcode\" in sys.modules') : 0")
    r = s.run()
    r.assert_ok()

    assert r.vars['python_used'] in (0, False), 'leetcode.py was imported'
    assert '  - Finished' in r.vars['test_result'], r.vars['test_result']
    assert '  - Accepted' in r.vars['submit_result'], r.vars['submit_result']
    assert '  - Faster than 95.5% submissions' in r.vars['submit_result']
    submission = r.text(r'^1\.two_sum\.123456\.cpp$')
    assert submission and 'Faster than 100.0% submissions' in submission, r.describe()
    assert 'return {0, 1};' in submission
    assert any('Given an array of integers nums' in l for l in r.vars['desc']), r.vars['desc']


@pytest.mark.python_only
def test_python_backend_needs_python(scenario, bare_vim_env):
    """For contrast: the default backend reports the missing packages."""
    s = scenario(env=bare_vim_env).let('leetcode_backend', 'python')
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    assert 'No module named' in r.output, r.describe()
