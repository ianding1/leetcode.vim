""":LeetCodeList and navigating the problem list."""

import json
import re

import pytest

LIST = r'^leetcode:///problems/all$'


def test_list_shows_problems(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    text = r.text(LIST)
    assert text is not None, r.describe()
    assert '## Problems (' in text, text
    assert 'Two Sum' in text


@pytest.mark.replay_only
def test_list_content_matches_api(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    lines = r.buffer(LIST)
    rows = [line for line in lines if re.match(r'^\|.\| \d+ ', line)]
    titles = [line.split('|')[3].strip() for line in rows]
    assert titles == ['Two Sum', 'Add Two Numbers', 'Median of Two Sorted Arrays',
                      'Binary Tree Upside Down [P]']   # hidden problem is skipped
    assert rows[0].startswith('|✓|') and rows[1].startswith('|~|'), rows
    assert '50.0%' in rows[0] and 'Easy' in rows[0]
    text = '\n'.join(lines)
    assert 'array:2' in text and 'hash-table:1' in text     # topics
    assert 'google:2' in text                                # companies
    assert 'All:4' in text and 'Easy:1' in text and 'Medium:2' in text


@pytest.mark.replay_only
def test_list_hides_paid_only(scenario, lc):
    s = scenario().signed_in(lc.cookies).let('leetcode_hide_paid_only', 1)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    text = r.text(LIST)
    assert 'Two Sum' in text
    assert 'Binary Tree Upside Down' not in text


@pytest.mark.replay_only
def test_list_filters_by_difficulty(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'\<Medium:')
    s.step('normal! f:b')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    text = r.text(LIST)
    assert re.search(r'^  Difficulty .*\[Medium:2\]', text, re.M), r.describe()
    assert 'Add Two Numbers' in text and 'Two Sum ' not in text


@pytest.mark.replay_only
@pytest.mark.parametrize('page', [
    {'status': 403, 'text': 'Forbidden'},
    {'status': 200, 'json': {'data': {'questionTopicTags': None, 'companyTags': None}}},
], ids=['http-error', 'unexpected-json'])
def test_list_survives_missing_topics(scenario, lc, page):
    """#78: used to fail with E684 in ListProblems."""
    lc.server.override('graphql.getTopicsAndCompanies', page)
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    assert 'Two Sum' in r.text(LIST)


def test_list_topics_are_present(scenario, lc):
    """Topics and companies come from GraphQL (getTopicsAndCompanies)."""
    s = scenario().signed_in(lc.cookies)
    s.step('call leetcode#SignIn(0)')
    s.capture('tc', 'leetcode#Api("GetTopicsAndCompanies")')
    r = s.run()
    r.assert_ok()
    tc = r.vars['tc']
    assert isinstance(tc, dict) and tc['topics'], r.describe()


def test_open_topic(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'\<array:')
    s.press('zv')                  # as a / search would
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    text = r.text(r'topic/array$')
    assert text and '# LeetCode [topic:array]' in text, r.describe()
    assert 'Two Sum' in text


@pytest.mark.replay_only
def test_open_company(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'\<google:')
    s.press('zv')                  # as a / search would
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    text = r.text(r'company/google$')
    assert text and '# LeetCode [company:google]' in text, r.describe()
    assert 'Add Two Numbers' in text


@pytest.mark.replay_only
def test_sort_by_title_descending(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.press(r'S3\<CR>2\<CR>')      # sort by "3 - Title", "2 - From high to low"
    r = s.run()
    r.assert_ok()
    lines = r.buffer(LIST)
    assert any(line.startswith('## Problems (4 shown · sorted by Title ↓)')
               for line in lines), r.describe()
    titles = [line.split('|')[3].strip() for line in lines if re.match(r'^\|.\| \d+ ', line)]
    assert titles == sorted(titles, reverse=True), titles


@pytest.mark.replay_only
def test_list_starts_at_the_problems(scenario, lc):
    """Topics and companies are folded away; the cursor is on the first problem."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.capture('line', "getline('.')")
    s.capture('topics_closed', "foldclosed(search('^## Topics (2)', 'nw')) != -1")
    s.capture('companies_closed', "foldclosed(search('^## Companies (1)', 'nw')) != -1")
    s.capture('fold_text', "foldtextresult(search('^## Topics', 'nw'))")
    r = s.run()
    r.assert_ok()
    assert re.match(r'^\|.\| 1 +\| Two Sum ', r.vars['line']), r.vars['line']
    assert r.vars['topics_closed'] and r.vars['companies_closed'], r.describe()
    assert r.vars['fold_text'].startswith('+ Topics (2)'), r.vars['fold_text']


@pytest.mark.replay_only
def test_enter_opens_a_section_and_it_stays_open(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'^## Topics')
    s.press(r'\<CR>')                  # opens the fold, doesn't navigate
    s.goto(r'\<Medium:')
    s.press(r'\<CR>')                  # redraws the list with a filter
    s.capture('topics_open', "foldclosed(search('^## Topics', 'nw')) == -1")
    s.capture('companies_closed', "foldclosed(search('^## Companies', 'nw')) != -1")
    r = s.run()
    r.assert_ok()
    assert '[Medium:2]' in r.text(LIST), r.describe()
    assert r.vars['topics_open'] and r.vars['companies_closed'], r.describe()


@pytest.mark.replay_only
def test_long_titles_are_cut(scenario, lc):
    long_title = 'A Problem Whose Title Goes On ' * 4
    problems = lc.server._lookup('problems', 'all')[1]
    problems = json.loads(json.dumps(problems))
    problems['json']['stat_status_pairs'][0]['stat']['question__title'] = long_title
    lc.server.override('problems', problems)
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    r = s.run()
    r.assert_ok()
    rows = [line for line in r.buffer(LIST) if re.match(r'^\|.\| \d+ ', line)]
    cell = rows[0].split('|')[3]
    assert cell.strip().endswith('…') and len(cell) <= 66, rows[0]
    assert 'Add Two Numbers' in rows[1]


def test_colors_follow_the_colorscheme(scenario, lc):
    """Highlights are defaults (hi def): a user's own setting wins, and they
    come back after :colorscheme clears them."""
    s = scenario().signed_in(lc.cookies)
    s.step('highlight lcHard ctermfg=123')
    s.step('LeetCodeList')
    s.capture('hard', "synIDattr(synIDtrans(hlID('lcHard')), 'fg', 'cterm')")
    s.step('colorscheme default')
    s.capture('easy_after', "execute('highlight lcEasy')")
    r = s.run()
    r.assert_ok()
    assert r.vars['hard'] == '123', r.vars
    assert 'ctermfg=' in r.vars['easy_after'] or 'links to' in r.vars['easy_after'], r.vars


@pytest.mark.replay_only
def test_list_summary_and_filters(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'\<Solved:')
    s.press(r'\<CR>')                  # Status: Solved
    s.goto(r'^  Difficulty')
    s.press(r'^\<CR>')                 # on the label: nothing changes
    r = s.run()
    r.assert_ok()
    text = r.text(LIST)
    assert re.search(r'^  Solved 1 of 4  \S+  25%$', text, re.M), text
    assert '  Easy 1/1 · Medium 0/2 · Hard 0/1' in text, text
    assert re.search(r'^  Status .*\[Solved:1\]', text, re.M), text
    assert re.search(r'^  Difficulty +\[All:', text, re.M), text
    assert [line.split('|')[3].strip() for line in rows_of(text)] == ['Two Sum'], text


def rows_of(text):
    return [line for line in text.split('\n') if re.match(r'^\|.\| \d+ ', line)]


@pytest.mark.replay_only
def test_table_is_drawn_with_box_lines(scenario, lc):
    """The text keeps | between cells; conceal draws them as box lines."""
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.step("let g:l = search('^|-|', 'nw')")
    s.capture('rule', "map(range(1, 4), 'synconcealed(g:l, v:val)')")
    s.capture('cursorline', '&cursorline')
    r = s.run()
    r.assert_ok()
    marks = [c[1] for c in r.vars['rule']]
    assert marks[0] == '' and marks[1:] == ['─', '┼', '─'], r.vars['rule']
    assert r.vars['cursorline'], r.vars
