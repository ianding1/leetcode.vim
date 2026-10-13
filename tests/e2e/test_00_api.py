"""The plugin's Python API (autoload/leetcode.py), one endpoint at a time.

These call the same functions the Vim commands use, but in isolation, so a
live run gives a per-endpoint answer even when a UI command fails early.
"""

import pytest

SLUG = 'two-sum'


def call(scenario, lc, expr):
    s = scenario().signed_in(lc.cookies)
    s.capture('value', "py3eval('{}')".format(expr.replace("'", "''")))
    r = s.run()
    r.assert_ok()
    value = r.vars['value']
    assert not (isinstance(value, dict) and 'capture_error' in value), \
        '{} raised: {}\n{}'.format(expr, value.get('capture_error'), r.describe())
    return value, r


def test_progress(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_progress()')
    assert isinstance(value, dict) and 'solvedTotal' in value, r.describe()


def test_problem_list(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_problems(["all"])')
    assert isinstance(value, list) and value, r.describe()
    two_sum = [p for p in value if p['slug'] == SLUG]
    assert two_sum and two_sum[0]['title'] == 'Two Sum'
    assert set(two_sum[0]) >= {'state', 'id', 'fid', 'title', 'slug', 'paid_only',
                               'ac_rate', 'level', 'frequency'}


def test_topics_and_companies(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_topics_and_companies()')
    assert isinstance(value, dict), 'expected a dict, got {!r}\n{}'.format(value, r.describe())
    assert value['topics'], r.describe()
    assert {'topic_name', 'topic_slug', 'num_problems'} <= set(value['topics'][0])


def test_problem_detail(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_problem("{}")'.format(SLUG))
    assert isinstance(value, dict), r.describe()
    assert value['title'] == 'Two Sum'
    assert value['desc'] and 'cpp' in value['templates']
    assert value['testcase'] and value['testable']


def test_problems_of_topic(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_problems_of_topic("array")')
    assert value['problems'], r.describe()
    assert any(p['slug'] == SLUG for p in value['problems'])


def test_problems_of_company(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_problems_of_company("google")')
    assert value['problems'], r.describe()


def test_submission_list(scenario, lc):
    value, r = call(scenario, lc, 'leetcode.get_submissions("{}")'.format(SLUG))
    assert isinstance(value, list), r.describe()
    if lc.live and not value:
        pytest.skip('no submissions for {} on this account'.format(SLUG))
    assert {'id', 'time', 'status', 'runtime'} <= set(value[0])


def test_submission_detail(scenario, lc):
    subs, r = call(scenario, lc, 'leetcode.get_submissions("{}")'.format(SLUG))
    if not isinstance(subs, list) or not subs:
        pytest.skip('no submission to open (see test_submission_list)')
    value, r = call(scenario, lc, 'leetcode.get_submission({})'.format(subs[0]['id']))
    assert isinstance(value, dict), r.describe()
    assert value['slug'] == SLUG and value['code'], r.describe()
    assert value['state'] != 'Unknown State', r.describe()
