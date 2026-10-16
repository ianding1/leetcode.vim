"""Opening a problem: description window and solution template."""

import re

import pytest

LIST = r'^leetcode:///problems/all$'


def open_two_sum(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press(r'\<CR>')
    return s


def test_open_problem_from_list(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.capture('ft', 'g:leetcode_solution_filetype')
    r = s.run()
    r.assert_ok()
    desc = r.text(r'^\[DESCRIPTION\] 1\.two-sum$')
    assert desc is not None, r.describe()
    assert desc.startswith('# 1. Two Sum\n'), desc
    assert 'array of integers `nums`' in desc, desc
    # Examples are code blocks, one line per line of the example.
    assert re.search(r'^```\nInput: .*\nOutput: ', desc, re.M), desc
    assert re.search(r'^https?://\S+/problems/two-sum/$', desc, re.M), desc
    if lc.live:
        assert re.search(r'^\*\*Easy\*\* · [\d.]+% accepted \(\S+ of \S+\)', desc, re.M), desc
        assert 'Topics: Array, Hash Table' in desc, desc
    else:
        assert '**Easy** · 50.0% accepted (4K of 8K) · 70.8K likes' in desc, desc
    solution = r.text(r'^1\.two_sum\.cpp$')
    assert solution is not None, r.describe()
    assert 'class Solution' in solution and 'twoSum' in solution


@pytest.mark.replay_only
def test_open_problem_uses_latest_submission(scenario, lc):
    """With a cpp submission on record, its code replaces the template."""
    r = open_two_sum(scenario, lc).run()
    r.assert_ok()
    solution = r.text(r'^1\.two_sum\.cpp$')
    assert 'e2e: solution from submission 123456' in solution, r.describe()
    assert 'vector<int>& nums' in solution


@pytest.mark.replay_only
def test_open_problem_falls_back_to_template(scenario, lc):
    lc.server.override('submissions', {'status': 200, 'json': {'submissions_dump': []}})
    r = open_two_sum(scenario, lc).run()
    r.assert_ok()
    solution = r.text(r'^1\.two_sum\.cpp$')
    assert 'e2e: solution' not in solution
    assert solution.splitlines()[0] == 'class Solution {'


def test_reset_solution(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('edit 1.two_sum.cpp')
    s.step('call setline(1, "garbage")')
    s.step('LeetCodeReset')
    r = s.run()
    r.assert_ok()
    solution = r.text(r'^1\.two_sum\.cpp$')
    assert 'garbage' not in solution and 'class Solution' in solution, r.describe()


def test_reset_keeps_solution_window(scenario, lc):
    """:LeetCodeReset on an open problem must not swap the solution window
    for the description buffer."""
    s = open_two_sum(scenario, lc)
    s.step('call setline(1, "garbage")')
    s.capture('before', "bufname('%')")
    s.step('LeetCodeReset')
    s.capture('after', "bufname('%')")
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    assert r.vars['before'] == '1.two_sum.cpp', r.describe()
    assert r.vars['after'] == '1.two_sum.cpp', r.vars
    assert '1.two_sum.cpp' in r.vars['windows'] and \
        any(w.startswith('[DESCRIPTION]') for w in r.vars['windows']), r.vars
    assert 'garbage' not in r.text(r'^1\.two_sum\.cpp$')


def test_reset_restores_hidden_description(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.step('wincmd k')
    s.step('close')                 # hide the description window
    s.step('LeetCodeReset')
    s.capture('current', "bufname('%')")
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    assert r.vars['current'] == '1.two_sum.cpp', r.vars
    assert any(w.startswith('[DESCRIPTION]') for w in r.vars['windows']), r.vars


def test_description_is_markdown(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.step('wincmd k')
    s.capture('ft', '&filetype')
    s.capture('wrap', '&wrap')
    s.capture('hints_closed', "foldclosed(search('^## Hints$', 'nw')) != -1")
    r = s.run()
    r.assert_ok()
    assert r.vars['ft'] == 'markdown' and r.vars['wrap'], r.vars
    assert r.vars['hints_closed'], r.describe()


@pytest.mark.replay_only
def test_description_hints_and_similar_questions(scenario, lc):
    lc.server.override('graphql.getQuestionDetail',
                       lc.server._lookup('graphql.getQuestionDetail', 'two-sum')[1],
                       key='add-two-numbers')
    s = open_two_sum(scenario, lc)
    s.step('wincmd k')
    s.goto(r'^- \[Add Two Numbers\]')
    s.press(r'\<CR>')                  # opens the similar question
    r = s.run()
    r.assert_ok()
    desc = r.text(r'^\[DESCRIPTION\] 1\.two-sum$')
    assert '## Hints\n\n1. A really brute force way' in desc, desc
    assert '2. Try a `hash map` to look up the complement.' in desc, desc
    assert re.search(r'^- \[Add Two Numbers\]\(\S+/problems/add-two-numbers/\) · Medium$',
                     desc, re.M), desc
    assert r.text(r'^2\.add_two_numbers\.cpp$') is not None, r.describe()
