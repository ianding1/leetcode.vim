""":LeetCodeTest and :LeetCodeSubmit, including the async worker thread."""

import json

import pytest

RESULT = r'^leetcode:///result$'
SOLUTION = r'''class Solution {
public:
    vector<int> twoSum(vector<int>& nums, int target) {
        unordered_map<int, int> seen;
        for (int i = 0; i < (int)nums.size(); ++i) {
            auto it = seen.find(target - nums[i]);
            if (it != seen.end()) return {it->second, i};
            seen[nums[i]] = i;
        }
        return {};
    }
};'''


def with_solution(scenario, lc, cookies=None):
    s = scenario().signed_in(cookies or lc.cookies)
    s.step('edit 1.two_sum.cpp')
    s.step('call setline(1, {})'.format(repr(SOLUTION.split('\n')).replace("'", '"')))
    s.step('write')
    return s


def test_run_with_default_testcase(scenario, lc):
    s = with_solution(scenario, lc)
    s.step('LeetCodeTest')
    s.capture('test_input', "getline(1, '$')")
    s.step('wq')                       # closing the input window starts the run
    s.wait_for_buffer(RESULT, 60000)
    r = s.run()
    r.assert_ok()
    assert r.vars['test_input'][0].startswith('# Test input for 1. Two Sum'), r.vars
    assert ':wq' in r.vars['test_input'][1] and ':LeetCodeTest' in r.vars['test_input'][1]
    assert r.vars['test_input'][2:] == ['[2,7,11,15]', '9'], r.vars
    result = r.text(RESULT)
    assert result is not None, r.describe()
    assert result.startswith('# Two Sum (test run)'), result
    assert '## State\n  - Accepted' in result, result
    assert '### Actual Answer\n    [0,1]' in result
    if not lc.live:
        sent = lc.server.requests_to('interpret_solution')[0]
        body = json.loads(sent['body'])
        assert body['lang'] == 'cpp' and 'unordered_map' in body['typed_code']
        assert body['data_input'] == '[2,7,11,15]\n9' and body['question_id'] == '1'
        assert sent['headers'].get('x-csrftoken') == 'e2e-csrf'


@pytest.mark.replay_only
def test_run_reports_wrong_answer(scenario, lc):
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'status_code': 10, 'status_runtime': '0 ms',
        'code_answer': ['[1,0]'], 'expected_code_answer': ['[0,1]'], 'code_output': []}}])
    s = with_solution(scenario, lc)
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    assert '## State\n  - Wrong Answer' in r.text(RESULT)


@pytest.mark.submits
def test_submit(scenario, lc):
    s = with_solution(scenario, lc)
    s.step('LeetCodeSubmit')
    s.wait_for_buffer(RESULT, 60000)
    r = s.run()
    r.assert_ok()
    result = r.text(RESULT)
    assert result is not None, r.describe()
    assert '## State\n  - Accepted' in result, result
    assert 'Faster than' in result
    assert '## Memory\n  - ' in result and 'less than' in result, result


@pytest.mark.replay_only
def test_submit_compile_error(scenario, lc):
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'judge_type': 'large', 'status_code': 20, 'status_runtime': 'N/A',
        'compile_error': 'Line 1: error: expected ;',
        'full_compile_error': 'Line 1: error: expected ;'}}])
    s = with_solution(scenario, lc)
    s.step('LeetCodeSubmit')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    result = r.text(RESULT)
    assert '## State\n  - Compile Error' in result
    assert 'expected ;' in result


@pytest.mark.replay_only
def test_submit_result_without_judge_type(scenario, lc):
    """#60: submissions were told apart from test runs by `judge_type ==
    'large'` in the result. Without it a submission was shown as a test run
    ("Finished", no expected output)."""
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'status_code': 11, 'status_runtime': 'N/A',
        'total_correct': 3, 'total_testcases': 57, 'code_output': '[1,0]',
        'expected_output': '[0,1]', 'std_output': '', 'last_testcase': '[3,2,4]\n6'}}])
    s = with_solution(scenario, lc)
    s.step('LeetCodeSubmit')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    result = r.text(RESULT)
    assert '## State\n  - Wrong Answer' in result, result
    assert '- Passed: 3' in result and '- Total:  57' in result
    assert '### Expected Answer\n    [0,1]' in result
    assert '### Input\n    [3,2,4]\n    6' in result


@pytest.mark.replay_only
def test_run_trusts_the_judges_verdict(scenario, lc):
    """A test run says Accepted or Wrong Answer, as the website does, using the
    judge's correct_answer; the wrong line of the answer is highlighted."""
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'status_code': 10, 'status_runtime': '0 ms',
        'code_answer': ['[0,1]', '[0,2]'], 'expected_code_answer': ['[0,1]', '[1,2]'],
        'code_output': [], 'correct_answer': False, 'total_correct': 1, 'total_testcases': 2}}])
    s = with_solution(scenario, lc)
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    s.capture('matches', "map(getmatches(win_getid(bufwinnr('leetcode:///result'))), "
                         "'[v:val.group, v:val.pos1[0]]')")
    s.capture('wrong_line', "search('^### Actual Answer$', 'nw') + 2")
    r = s.run()
    r.assert_ok()
    result = r.text(RESULT)
    assert '## State\n  - Wrong Answer' in result, result
    assert '- Passed: 1' in result and '- Total:  2' in result, result
    # Only the second answer line differs.
    lines = [line for group, line in r.vars['matches'] if group == 'lcMismatch']
    assert len(lines) == 1, r.vars['matches']


@pytest.mark.replay_only
def test_run_does_not_mark_the_problem_solved(scenario, lc):
    """Only submissions change a problem's status in the list. (A test run
    used to turn a solved problem into an attempted one.)"""
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'status_code': 10, 'status_runtime': '0 ms',
        'code_answer': ['[1,0]'], 'expected_code_answer': ['[0,1]'],
        'code_output': [], 'correct_answer': False}}])
    s = with_solution(scenario, lc)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.capture('before', "matchstr(getline('.'), '^|\\zs[^|]*')")
    s.step('edit 1.two_sum.cpp')
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    s.step('buffer leetcode:///problems/all')
    s.goto(r'\<Easy:')
    s.press(r'\<CR>')                  # redraws from the list's own data
    s.goto(r'| Two Sum ')
    s.capture('after', "matchstr(getline('.'), '^|\\zs[^|]*')")
    r = s.run()
    r.assert_ok()
    assert r.vars['before'] == r.vars['after'] == '✓', r.describe()


def test_test_command_in_the_input_window_runs_the_test(scenario, lc):
    s = with_solution(scenario, lc)
    s.step('LeetCodeTest')
    s.step('LeetCodeTest')              # in the input window: run it
    s.wait_for_buffer(RESULT, 60000)
    r = s.run()
    r.assert_ok()
    assert '## State\n  - Accepted' in r.text(RESULT), r.describe()


@pytest.mark.parametrize('window', ['test input', 'description', 'result'])
def test_submit_from_a_window_of_the_problem(scenario, lc, window):
    """:LeetCodeSubmit used to take the problem from the current file name,
    and failed in the test input or description window."""
    if lc.live:
        pytest.skip('would make a real submission')
    s = with_solution(scenario, lc)
    if window == 'test input':
        s.step('LeetCodeTest')
    elif window == 'description':
        s.step('call leetcode#ResetSolution(0)')
        s.step('wincmd h')
    else:
        s.step('LeetCodeTest')
        s.step('wq')
        s.wait_for_buffer(RESULT)
        s.step('wincmd b')
    s.capture('buffer', "bufname('%')")
    s.step('LeetCodeSubmit')
    s.wait_for('!leetcode#Busy()')
    r = s.run()
    r.assert_ok()
    assert not r.vars['buffer'].endswith('.cpp'), r.vars
    assert lc.server.requests_to('submit')[0]['path'] == '/problems/two-sum/submit/', r.describe()
    assert '## State\n  - Accepted' in r.text(RESULT), r.describe()


def test_submit_outside_a_solution(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeSubmit')
    r = s.run()
    r.assert_ok()
    assert 'this is not a solution file' in r.output, r.describe()


@pytest.mark.replay_only
def test_submit_error_says_why(scenario, lc):
    lc.server.override('submit', {'status': 403, 'text': 'Forbidden'})
    s = with_solution(scenario, lc)
    s.step('LeetCodeSubmit')
    s.wait_for('!leetcode#Busy()')
    r = s.run()
    r.assert_ok()
    assert 'cannot submit the solution for two-sum (HTTP 403)' in r.output, r.describe()


@pytest.mark.replay_only
@pytest.mark.parametrize('command', ['test', 'submit'])
def test_signed_in_with_the_session_only(scenario, lc, command):
    """Users often paste only LEETCODE_SESSION. LeetCode then refused runs
    and submissions (HTTP 499): the plugin now gets the CSRF token itself."""
    s = with_solution(scenario, lc, {'LEETCODE_SESSION': 'e2e-session'})
    if command == 'test':
        s.step('LeetCodeTest')
        s.step('wq')
    else:
        s.step('LeetCodeSubmit')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    assert '## State\n  - Accepted' in r.text(RESULT), r.describe()


@pytest.mark.replay_only
def test_stale_csrf_token_is_renewed(scenario, lc):
    """When LeetCode turns the token down (499), the plugin gets a new one and
    tries once more."""
    lc.server.csrf_tokens = ['stale', 'fresh']     # sign-in gets 'stale'
    lc.server.valid_csrf_tokens = {'fresh'}
    s = with_solution(scenario, lc)
    s.step('LeetCodeSubmit')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    assert '## State\n  - Accepted' in r.text(RESULT), r.describe()
    assert [q['status'] for q in lc.server.requests_to('submit')] == [499, 200]


@pytest.mark.parametrize('how', ['opened', 'edited'])
def test_python_solution_runs_without_asking_which_python(scenario, lc, how):
    """.py is Python 2 or 3; the plugin used to ask on every run."""
    s = scenario().signed_in(lc.cookies).let('leetcode_solution_filetype', 'python3')
    if how == 'opened':
        s.step('LeetCodeOpen 1')
    else:
        s.step('edit 1.two_sum.py')
        s.step('call setline(1, ["class Solution:", "    def twoSum(self, nums, target):",'
               ' "        return [0, 1]"])')
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(RESULT, 60000)
    r = s.run()
    r.assert_ok()
    assert 'Which Python' not in r.output, r.output
    if not lc.live:
        assert json.loads(lc.server.requests_to('interpret_solution')[0]['body'])['lang'] \
            == 'python3'
