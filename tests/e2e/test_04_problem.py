"""Opening a problem: description window and solution template."""

import json
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
    solution = r.text(r'^p0001_two_sum\.cpp$')
    assert solution is not None, r.describe()
    assert 'class Solution' in solution and 'twoSum' in solution


@pytest.mark.replay_only
def test_open_problem_uses_latest_submission(scenario, lc):
    """With a cpp submission on record, its code replaces the template."""
    r = open_two_sum(scenario, lc).run()
    r.assert_ok()
    solution = r.text(r'^p0001_two_sum\.cpp$')
    assert 'e2e: solution from submission 123456' in solution, r.describe()
    assert 'vector<int>& nums' in solution


@pytest.mark.replay_only
def test_open_problem_falls_back_to_template(scenario, lc):
    lc.server.override('submissions', {'status': 200, 'json': {'submissions_dump': []}})
    r = open_two_sum(scenario, lc).run()
    r.assert_ok()
    solution = r.text(r'^p0001_two_sum\.cpp$')
    assert 'e2e: solution' not in solution
    assert solution.splitlines()[0] == 'class Solution {'


def test_reset_solution(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('edit p0001_two_sum.cpp')
    s.step('call setline(1, "garbage")')
    s.step('LeetCodeReset')
    r = s.run()
    r.assert_ok()
    solution = r.text(r'^p0001_two_sum\.cpp$')
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
    assert r.vars['before'] == 'p0001_two_sum.cpp', r.describe()
    assert r.vars['after'] == 'p0001_two_sum.cpp', r.vars
    assert 'p0001_two_sum.cpp' in r.vars['windows'] and \
        any(w.startswith('[DESCRIPTION]') for w in r.vars['windows']), r.vars
    assert 'garbage' not in r.text(r'^p0001_two_sum\.cpp$')


def test_reset_restores_hidden_description(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.step('wincmd h')
    s.step('close')                 # hide the description window
    s.step('LeetCodeReset')
    s.capture('current', "bufname('%')")
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    assert r.vars['current'] == 'p0001_two_sum.cpp', r.vars
    assert any(w.startswith('[DESCRIPTION]') for w in r.vars['windows']), r.vars


def test_description_is_markdown(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.step('wincmd h')
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
    s.step('wincmd h')
    s.goto(r'^- \[Add Two Numbers\]')
    s.press(r'\<CR>')                  # opens the similar question
    r = s.run()
    r.assert_ok()
    desc = r.text(r'^\[DESCRIPTION\] 1\.two-sum$')
    assert '## Hints\n\n1. A really brute force way' in desc, desc
    assert '2. Try a `hash map` to look up the complement.' in desc, desc
    assert re.search(r'^- \[Add Two Numbers\]\(\S+/problems/add-two-numbers/\) · Medium$',
                     desc, re.M), desc
    assert r.text(r'^p0002_add_two_numbers\.cpp$') is not None, r.describe()


def test_new_solution_is_saved_in_the_current_directory(scenario, lc):
    """By default a new solution is written to the current directory at once:
    no "modified" flag, no question of where to save it."""
    s = scenario().signed_in(lc.cookies).unlet('leetcode_solution_dir')
    s.step('LeetCodeOpen 1')
    s.capture('path', "expand('%:p')")
    s.capture('cwd', "getcwd()")
    s.capture('modified', '&modified')
    s.capture('on_disk', "readfile(expand('%:p'))")
    r = s.run()
    r.assert_ok()
    assert r.vars['path'] == r.vars['cwd'] + '/p0001_two_sum.cpp', r.vars
    assert not r.vars['modified'], r.vars
    assert any('twoSum' in line for line in r.vars['on_disk']), r.vars


def test_existing_solution_is_opened_as_it_is(scenario, lc):
    """Opening a problem used to replace the file's code with the template or
    the last submission, so saving lost your work."""
    s = scenario().signed_in(lc.cookies)
    s.step('call writefile(["// my work in progress"], "1.two_sum.cpp")')
    s.step('LeetCodeOpen 1')
    s.capture('lines', "getline(1, '$')")
    s.capture('modified', '&modified')
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    assert r.vars['lines'] == ['// my work in progress'], r.vars
    assert not r.vars['modified'], r.vars
    assert any(w.startswith('[DESCRIPTION] 1.two-sum') for w in r.vars['windows']), r.vars


def test_problem_opens_side_by_side_instead_of_the_list(scenario, lc):
    s = open_two_sum(scenario, lc)
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    s.capture('layout', 'winlayout()[0]')
    s.capture('list_loaded', "bufloaded('leetcode:///problems/all')")
    s.step('LeetCodeList')
    s.capture('back', "bufname('%')")
    r = s.run()
    r.assert_ok()
    assert [w.split('/')[-1] for w in r.vars['windows']] == [
        '[DESCRIPTION] 1.two-sum', 'p0001_two_sum.cpp'], r.vars['windows']
    assert r.vars['layout'] == 'row', r.vars                # side by side
    assert r.vars['list_loaded'], 'the list is kept, hidden'
    assert r.vars['back'] == 'leetcode:///problems/all', r.vars


@pytest.mark.replay_only
def test_similar_question_replaces_the_current_one(scenario, lc):
    detail = json.loads(json.dumps(lc.server._lookup('graphql.getQuestionDetail', 'two-sum')[1]))
    detail['json']['data']['question'].update(questionFrontendId='2', title='Add Two Numbers')
    lc.server.override('graphql.getQuestionDetail', detail, key='add-two-numbers')
    s = open_two_sum(scenario, lc)
    s.step('wincmd h')
    s.goto(r'^- \[Add Two Numbers\]')
    s.press(r'\<CR>')
    s.capture('windows', "map(range(1, winnr('$')), 'bufname(winbufnr(v:val))')")
    r = s.run()
    r.assert_ok()
    assert [w.split('/')[-1] for w in r.vars['windows']] == [
        '[DESCRIPTION] 2.add-two-numbers', 'p0002_add_two_numbers.cpp'], r.vars['windows']


def test_old_style_file_names_still_work(scenario, lc):
    """Solutions saved as 1.two_sum.cpp by earlier versions keep working."""
    s = scenario().signed_in(lc.cookies)
    s.step('edit 1.two_sum.cpp')
    s.step('call setline(1, ["class Solution {};"])')
    s.step('write')
    s.step('LeetCodeTest')
    s.capture('header', 'getline(1)')
    s.step('q!')
    r = s.run()
    r.assert_ok()
    assert r.vars['header'].startswith('# 1. Two Sum:'), r.vars


@pytest.mark.replay_only
def test_problems_numbered_otherwise_use_the_slug(scenario, lc):
    """leetcode.cn numbers some problems like "LCP 01": the file is named after
    the slug alone, still a valid identifier."""
    detail = json.loads(json.dumps(lc.server._lookup('graphql.getQuestionDetail', 'two-sum')[1]))
    detail['json']['data']['question']['questionFrontendId'] = 'LCP 01'
    lc.server.override('graphql.getQuestionDetail', detail)
    problems = json.loads(json.dumps(lc.server._lookup('problems', 'all')[1]))
    problems['json']['stat_status_pairs'][0]['stat']['frontend_question_id'] = 'LCP 01'
    lc.server.override('problems', problems)
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeOpen two-sum')
    s.capture('name', "expand('%:t')")
    r = s.run()
    r.assert_ok()
    assert r.vars['name'] == 'two_sum.cpp', r.vars


def test_solution_dir_option(scenario, lc):
    s = scenario().signed_in(lc.cookies).let('leetcode_solution_dir', '~/solutions')
    s.step('LeetCodeOpen 1')
    s.capture('path', "expand('%:p')")
    s.capture('home', "expand('~')")
    r = s.run()
    r.assert_ok()
    assert r.vars['path'] == r.vars['home'] + '/solutions/p0001_two_sum.cpp', r.vars
