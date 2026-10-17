"""Listing and opening past submissions (`s` in the problem list)."""

import json
import re

import pytest

SUBS = r'^leetcode:///submissions/two-sum$'


def test_list_submissions(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    r = s.run()
    r.assert_ok()
    text = r.text(SUBS)
    assert text is not None, r.describe()
    assert text.startswith('# 1. Two Sum · Submissions'), text
    assert '| ID ' in text and '| Language ' in text and ' Memory |' in text, text


@pytest.mark.replay_only
def test_open_submission(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^|.| 123456 ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    subs = r.text(SUBS)
    assert '  2 submissions · 1 accepted' in subs, subs
    assert re.search(r'^\|✓\| 123456 \| 1 hour ago +\| Accepted +\| C\+\+ +\| +4 ms '
                     r'\| 10\.1 MB \|$', subs, re.M), subs
    assert re.search(r'^\|✗\| 123400 .*\| Wrong Answer .*\| Python3 ', subs, re.M), subs
    text = r.text(r'^1\.two_sum\.123456\.cpp$')
    assert text is not None, r.describe()
    assert text.startswith('/* Submission 123456 · Two Sum\n'
                           ' * Accepted · 57/57 test cases passed\n'), text
    assert 'return {0, 1};' in text


@pytest.mark.replay_only
def test_open_submission_shows_runtime_rank(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^|.| 123456 ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    assert (' * Runtime 4 ms, faster than 100.0% · Memory 10.1 MB, less than 60.2%'
            in r.text(r'^1\.two_sum\.123456\.cpp$')), r.describe()


@pytest.mark.replay_only
def test_past_submission_is_a_scratch_buffer(scenario, lc):
    """It's there to read or start from, so closing it doesn't ask to save."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^|.| 123456 ')
    s.press(r'\<CR>')
    s.capture('buftype', '&buftype')
    r = s.run()
    r.assert_ok()
    assert r.vars['buftype'] == 'nofile', r.vars


@pytest.mark.replay_only
def test_submissions_replace_the_list_and_open_side_by_side(scenario, lc):
    wrong = json.loads(json.dumps(lc.server._lookup('graphql.submissionDetails', '123456')[1]))
    wrong['json']['data']['submissionDetails'].update(
        statusCode=11, totalCorrect=3, lang={'name': 'python3'}, code='class Solution: pass\n',
        lastTestcase='[3,2,4]\n6', codeOutput='[0,1]', expectedOutput='[1,2]',
        runtimeDisplay='N/A', memoryDisplay='', runtimePercentile=None, memoryPercentile=None)
    lc.server.override('graphql.submissionDetails', wrong, key='123400')
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.press('s')                        # cursor starts on Two Sum
    s.capture('after_s', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    s.goto(r'^|.| 123456 ')
    s.press(r'\<CR>')
    s.step('wincmd h')                  # back to the submissions
    s.goto(r'^|.| 123400 ')
    s.press(r'\<CR>')                  # replaces the view next to the list
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    s.step('wincmd h')
    s.press('q')
    s.capture('back', "bufname('%')")
    r = s.run()
    r.assert_ok()
    assert r.vars['after_s'] == ['leetcode:///submissions/two-sum'], r.vars
    assert r.vars['windows'] == ['leetcode:///submissions/two-sum',
                                 '1.two_sum.123400.py'], r.describe()
    assert r.vars['back'] == 'leetcode:///problems/all', r.vars
    view = r.text(r'^1\.two_sum\.123400\.py$')
    assert view.startswith('# Submission 123400 · Two Sum\n'
                           '# Wrong Answer · 3/57 test cases passed\n'
                           '# Input:\n#     [3,2,4]\n#     6\n# Output:\n#     [0,1]\n'
                           '# Expected:\n#     [1,2]\n'), view


@pytest.mark.replay_only
def test_submitting_a_past_submission_sends_only_its_code(scenario, lc):
    """The view starts with a comment about the submission; it isn't sent."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.press('s')
    s.goto(r'^|.| 123456 ')
    s.press(r'\<CR>')
    s.step('LeetCodeSubmit')
    s.wait_for('!leetcode#Busy()')
    r = s.run()
    r.assert_ok()
    code = json.loads(lc.server.requests_to('submit')[0]['body'])['typed_code']
    assert code.startswith('class Solution {') and 'Submission 123456' not in code, code
