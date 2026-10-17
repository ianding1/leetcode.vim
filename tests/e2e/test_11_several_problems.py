"""Working on several problems at once: each window keeps to its problem."""

import json

import pytest

pytestmark = pytest.mark.replay_only

RESULT = r'^leetcode:///result$'
WINDOWS = "map(range(1, winnr('$')), 'fnamemodify(bufname(winbufnr(v:val)), \":t\")')"


@pytest.fixture
def two_problems(lc):
    """Problem 2 (Add Two Numbers) answers with Two Sum's details."""
    d = json.loads(json.dumps(lc.server._lookup('graphql.getQuestionDetail', 'two-sum')[1]))
    d['json']['data']['question'].update(questionFrontendId='2', questionId='2',
                                         title='Add Two Numbers')
    lc.server.override('graphql.getQuestionDetail', d, key='add-two-numbers')


def test_each_test_input_runs_its_own_problem(scenario, lc, two_problems):
    """The input of problem 1, closed after :LeetCodeTest was run on problem 2,
    used to be sent with problem 2's code to problem 2."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeTest')
    s.step('let g:in1 = bufnr("%")')
    s.step('call setline(5, ["[1,1]", "2"])')
    s.step(':tab LeetCodeOpen 2')
    s.step('LeetCodeTest')
    s.step('tabfirst')
    s.step('execute bufwinnr(g:in1) . "wincmd w"')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    run = lc.server.requests_to('interpret_solution')
    assert [q['path'] for q in run] == ['/problems/two-sum/interpret_solution/'], run
    body = json.loads(run[0]['body'])
    assert body['data_input'].startswith('[1,1]\n2\n') and body['question_id'] == '1', body
    assert '# Two Sum (test run)' in r.text(RESULT)


def test_one_test_input_window_per_problem(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeTest')
    s.step('wincmd p')
    s.step('LeetCodeTest')              # again: goes to the open one
    s.capture('windows', 'winnr("$")')
    s.capture('current', 'exists("b:leetcode_test")')
    s.step('q!')
    r = s.run()
    r.assert_ok()
    assert r.vars['windows'] == 3 and r.vars['current'], r.vars


def test_test_runs_the_code_as_it_is_when_the_input_is_closed(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeTest')
    s.step('wincmd p')
    s.step('call append("$", "// edited while the input was open")')
    s.step('wincmd p')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    r = s.run()
    r.assert_ok()
    code = json.loads(lc.server.requests_to('interpret_solution')[0]['body'])['typed_code']
    assert code.endswith('// edited while the input was open'), code


def test_quitting_the_input_runs_nothing(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeTest')
    s.step('q!')
    r = s.run()
    r.assert_ok()
    assert lc.server.requests_to('interpret_solution') == []


def test_switching_problems_brings_their_descriptions(scenario, lc, two_problems):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeOpen 2')
    s.capture('two', WINDOWS)
    s.step('LeetCodeOpen 1')            # its solution is open already
    s.capture('one', WINDOWS)
    r = s.run()
    r.assert_ok()
    assert r.vars['two'] == ['[DESCRIPTION] 2.add-two-numbers', 'p0002_add_two_numbers.cpp'], r.vars
    assert r.vars['one'] == ['[DESCRIPTION] 1.two-sum', 'p0001_two_sum.cpp'], r.vars


def test_unsaved_solution_keeps_its_description(scenario, lc, two_problems):
    """Problem 1 has unsaved changes, so problem 2 opens beside it; each
    solution keeps its description on its left."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('call append(0, "// unsaved")')
    s.step('LeetCodeOpen 2')
    s.capture('windows', WINDOWS)
    r = s.run()
    r.assert_ok()
    assert r.vars['windows'] == ['[DESCRIPTION] 1.two-sum', 'p0001_two_sum.cpp',
                                 '[DESCRIPTION] 2.add-two-numbers', 'p0002_add_two_numbers.cpp'], \
        r.vars


def test_tab_modifier_opens_a_problem_in_its_own_tab(scenario, lc, two_problems):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('tab LeetCodeOpen 2')
    s.capture('tabs', 'tabpagenr("$")')
    s.capture('second', WINDOWS)
    s.step('tabfirst')
    s.capture('first', WINDOWS)
    r = s.run()
    r.assert_ok()
    assert r.vars['tabs'] == 2, r.vars
    assert r.vars['second'] == ['[DESCRIPTION] 2.add-two-numbers',
                                'p0002_add_two_numbers.cpp'], r.vars
    assert r.vars['first'] == ['[DESCRIPTION] 1.two-sum', 'p0001_two_sum.cpp'], r.vars


def test_a_second_run_starts_clean_and_cancelling_it_runs_nothing(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen 1')
    s.step('LeetCodeTest')
    s.step('wq')
    s.wait_for_buffer(RESULT)
    s.step('pclose')
    s.step('LeetCodeTest')
    s.capture('again', "getline(1, '$')")
    s.step('q!')
    r = s.run()
    r.assert_ok()
    assert len(lc.server.requests_to('interpret_solution')) == 1, 'the cancelled run was sent'
    assert [line for line in r.vars['again'] if line.startswith('#')] == [
        '# 1. Two Sum: one argument per line (nums, target),',
        '# a blank line between cases. Add your own.',
        '# :wq (or :LeetCodeTest) runs them; :q! cancels.'], r.vars['again']
