""":LeetCodeTest and :LeetCodeSubmit, including the async worker thread."""

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


def with_solution(scenario, lc):
    s = scenario().signed_in(lc.cookies)
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
    assert r.vars['test_input'][0] == '# Test Input'
    result = r.text(RESULT)
    assert result is not None, r.describe()
    assert '## State\n  - Finished' in result, result
    assert '### Actual Answer\n    [0,1]' in result
    if not lc.live:
        sent = lc.server.requests_to('interpret_solution')[0]
        assert '"lang": "cpp"' in sent['body'] and 'unordered_map' in sent['body']
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


@pytest.mark.replay_only
def test_submit_compile_error(scenario, lc):
    lc.server.override('check', [{'status': 200, 'json': {
        'state': 'SUCCESS', 'judge_type': 'large', 'status_code': 20, 'status_runtime': 'N/A',
        'compile_error': 'Line 1: error: expected ;', 'full_compile_error': 'Line 1: error: expected ;'}}])
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
