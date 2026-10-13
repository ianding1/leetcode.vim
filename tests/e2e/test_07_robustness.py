"""Bugs found by code review: error paths and edge cases in the UI and API layer."""

import pytest

pytestmark = pytest.mark.replay_only

RESULT = r'^leetcode:///result$'
SOLUTION = ['class Solution {', 'public:',
            '    vector<int> twoSum(vector<int>& nums, int target) { return {0, 1}; }', '};']


def with_solution(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('edit 1.two_sum.cpp')
    s.step('call setline(1, {})'.format(str(SOLUTION).replace("'", '"')))
    s.step('write')
    return s


def run_test(s):
    s.step('LeetCodeTest')
    s.step('wq')
    return s


def test_company_time_period_key(scenario, lc):
    """`t` in a company list was mapped to `s:ChooseTimePeriod()`, which a
    mapping cannot call (E81/E117)."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'\<google:')
    s.press(r'\<CR>')
    s.press(r't2\<CR>')            # `t`, then "2 - 1 year"
    r = s.run()
    r.assert_ok()
    assert not any('E81' in l or 'E117' in l or 'E120' in l for l in r.output.split('\n')), \
        r.describe()
    assert 'Time period: one-year' in r.text(r'company/google$'), r.describe()


def test_async_task_is_not_done_when_started(scenario, lc):
    """The status timer must not see the previous task's `task_done` flag."""
    s = with_solution(scenario, lc)
    run_test(s)
    s.wait_for_buffer(RESULT)
    s.capture('done_after_start', "py3eval('[leetcode.test_solution_async(1, \"Two Sum\", "
                                  "\"two-sum\", \"cpp\", \"x\", \"[1]\\\\n1\"), "
                                  "leetcode.task_done][1]')")
    r = s.run()
    r.assert_ok()
    assert r.vars['done_after_start'] in (0, False), r.describe()


def test_run_with_unexpected_judge_state(scenario, lc):
    """An unknown judge state used to make the worker poll forever."""
    lc.server.override('check', [{'status': 200, 'json': {'state': 'FAILURE'}}])
    s = run_test(with_solution(scenario, lc))
    s.wait_for('empty(timer_info())', 20000)
    r = s.run()
    r.assert_ok()
    assert 'FAILURE' in r.output, r.describe()


def test_run_when_result_cannot_be_fetched(scenario, lc):
    lc.server.override('check', [{'status': 500, 'text': 'oops'}])
    s = run_test(with_solution(scenario, lc))
    s.wait_for('empty(timer_info())', 20000)
    r = s.run()
    r.assert_ok()
    assert 'cannot get the execution result' in r.output, r.describe()
    assert 'NoneType' not in r.output, r.describe()


def test_run_rejected_by_judge(scenario, lc):
    """An error body instead of an interpret_id used to surface as KeyError."""
    lc.server.override('interpret_solution', {'status': 200, 'json': {
        'error': 'You have attempted to run code too soon.'}})
    s = run_test(with_solution(scenario, lc))
    s.wait_for('empty(timer_info())', 20000)
    r = s.run()
    r.assert_ok()
    assert 'too soon' in r.output, r.describe()
    assert 'KeyError' not in r.output, r.describe()


def test_test_on_unknown_problem(scenario, lc):
    """:LeetCodeTest in a file whose problem can't be fetched used to raise E716."""
    s = scenario().signed_in(lc.cookies)
    s.step('edit 9999.no_such_problem.cpp')
    s.step('LeetCodeTest')
    r = s.run()
    r.assert_ok()
    assert 'cannot get the problem: no-such-problem' in r.output, r.describe()


def test_unsupported_solution_filetype(scenario, lc):
    s = scenario().signed_in(lc.cookies).let('leetcode_solution_filetype', 'cobol')
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    assert 'the file type is not supported: cobol' in r.output, r.describe()


def test_typescript_solution(scenario, lc):
    """PR #63: TypeScript is a LeetCode language."""
    lc.server.override('submissions', {'status': 200, 'json': {'submissions_dump': []}})
    s = scenario().signed_in(lc.cookies).let('leetcode_solution_filetype', 'typescript')
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    assert r.text(r'^1\.two_sum\.ts$') is not None, r.describe()
    assert r.text(r'DESCRIPTION').startswith('/* Two Sum')


def test_open_submission_in_unknown_language(scenario, lc):
    page = lc.server._lookup('submission_page', '123456')[1]['text']
    lc.server.override('submission_page', {'status': 200, 'text': page.replace(
        "getLangDisplay: 'cpp'", "getLangDisplay: 'erlang'")})
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^| 123456 ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    assert any(name.startswith('1.two_sum.123456.') for name in r.buffers), r.describe()
