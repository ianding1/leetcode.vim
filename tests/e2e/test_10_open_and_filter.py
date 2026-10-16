""":LeetCodeOpen and filtering the problem list."""

import re

import pytest

LIST = r'^leetcode:///problems/all$'
SOLUTION = r'^1\.two_sum\.cpp$'


def rows(r):
    return [line for line in r.buffer(LIST) if re.match(r'^\|.\| \d+ ', line)]


@pytest.mark.parametrize('name', ['1', 'two-sum'])
def test_open_by_number_or_slug(scenario, lc, name):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen ' + name)
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    solution = r.text(SOLUTION)
    assert solution and 'twoSum' in solution, r.describe()
    # The empty window is reused: just the description and the solution.
    assert len(r.vars['windows']) == 2, r.vars['windows']
    assert r.vars['windows'][0].startswith('[DESCRIPTION] 1.two-sum'), r.vars['windows']


@pytest.mark.replay_only
def test_open_unknown_problem(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen no-such-problem')
    r = s.run()
    r.assert_ok()
    assert "no problem 'no-such-problem'" in r.output, r.describe()


def test_open_completes_slugs(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.capture('slugs', "getcompletion('LeetCodeOpen two-', 'cmdline')")
    r = s.run()
    r.assert_ok()
    assert 'two-sum' in r.vars['slugs'], r.vars


def test_completion_never_asks_to_sign_in(scenario):
    """Tab must not start a sign-in prompt (headless Vim would exit on it)."""
    s = scenario()
    s.capture('slugs', "getcompletion('LeetCodeOpen ', 'cmdline')")
    r = s.run()
    r.assert_ok()
    assert r.vars['slugs'] == [], r.vars


@pytest.mark.replay_only
def test_filter_and_clear(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.press(r'ftwo\<CR>')               # f, then the prompt's answer
    s.capture('filtered', "getline(1, '$')")
    s.capture('line', "getline('.')")
    s.press('F')
    r = s.run()
    r.assert_ok()
    filtered = [line for line in r.vars['filtered'] if re.match(r'^\|.\| \d+ ', line)]
    assert [line.split('|')[3].strip() for line in filtered] == [
        'Two Sum', 'Add Two Numbers', 'Median of Two Sorted Arrays'], filtered
    assert any('3 shown · filter "two"' in line for line in r.vars['filtered'])
    assert '| Two Sum ' in r.vars['line'], r.vars['line']
    assert len(rows(r)) == 4, r.describe()


@pytest.mark.replay_only
def test_filter_by_number(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.press(r'f156\<CR>')
    r = s.run()
    r.assert_ok()
    assert [line.split('|')[2].strip() for line in rows(r)] == ['156'], rows(r)
