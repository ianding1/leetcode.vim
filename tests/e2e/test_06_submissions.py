"""Listing and opening past submissions (`s` in the problem list)."""

import pytest

SUBS = r'^leetcode:///submissions/two-sum$'


def test_list_submissions(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    r = s.run()
    r.assert_ok()
    text = r.text(SUBS)
    assert text is not None, r.describe()
    assert '## Submissions' in text and '| ID ' in text


@pytest.mark.replay_only
def test_open_submission(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^| 123456 ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    assert '| 123456 | 1 hour ago' in r.text(SUBS)
    text = r.text(r'^1\.two_sum\.123456\.cpp$')
    assert text is not None, r.describe()
    assert '/* Submission 123456' in text
    assert ' *   - Accepted' in text
    assert 'return {0, 1};' in text


@pytest.mark.replay_only
@pytest.mark.xfail(strict=True, reason="FormatResult tests `if string(percentile)`; for a "
                                       "string like '100.0%' that is \"'100.0%'\", which "
                                       "Vim treats as 0, so the rank is never shown")
def test_open_submission_shows_runtime_rank(scenario, lc):
    s = scenario().signed_in(lc.cookies)
    s.step('LeetCodeList')
    s.goto(r'| Two Sum ')
    s.press('s')
    s.goto(r'^| 123456 ')
    s.press(r'\<CR>')
    r = s.run()
    r.assert_ok()
    # 4 ms is the fastest bucket in the fixture's runtime distribution.
    assert 'Faster than 100.0%' in r.text(r'^1\.two_sum\.123456\.cpp$')
