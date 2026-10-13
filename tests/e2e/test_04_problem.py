"""Opening a problem: description window and solution template."""

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
    assert desc.startswith('/* Two Sum')
    assert '[End of Description] */' in desc
    assert 'Given an array of integers nums' in desc
    assert '[Easy] [AC:50.0% 4K of 8K] [filetype:cpp]' in desc
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
