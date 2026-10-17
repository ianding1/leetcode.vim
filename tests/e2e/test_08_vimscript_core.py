"""Python-free building blocks: HTTP through curl, HTML to text in Vim script.

Not wired into the plugin yet. These tests pin their behaviour in Vim and
Neovim so the Python code can be replaced piece by piece.
"""

import json

import pytest

pytestmark = pytest.mark.replay_only


def vim_json(value):
    """A Vim expression that evaluates to `value`."""
    return "json_decode('{}')".format(json.dumps(value).replace("'", "''"))


def request_sync(scenario, opts):
    s = scenario()
    s.capture('res', 'leetcode#http#Request({})'.format(vim_json(opts)))
    r = s.run()
    r.assert_ok()
    return r.vars['res'], r


def request_async(scenario, opts):
    s = scenario()
    s.step('let g:res = {}')
    s.step('call leetcode#http#RequestAsync({}, {{r -> extend(g:res, r)}})'.format(vim_json(opts)))
    s.wait_for('has_key(g:res, "status")', 20000)
    s.capture('res', 'g:res')
    r = s.run()
    r.assert_ok()
    return r.vars['res'], r


@pytest.mark.parametrize('send', [request_sync, request_async], ids=['sync', 'async'])
def test_get_with_cookies_and_headers(scenario, lc, send):
    res, r = send(scenario, {
        'url': lc.base_url + '/api/progress/all/',
        'cookies': {'LEETCODE_SESSION': 'abc', 'csrftoken': 'tok'},
        'headers': {'X-CSRFToken': 'tok', 'Referer': lc.base_url},
    })
    assert res['error'] == '' and res['status'] == 200, r.describe()
    assert json.loads(res['body'])['solvedTotal'] == 1
    assert res['headers']['content-type'] == 'application/json'
    sent = lc.server.requests_to('progress')[0]
    assert sent['headers']['cookie'] == 'LEETCODE_SESSION=abc; csrftoken=tok'
    assert sent['headers']['x-csrftoken'] == 'tok'


@pytest.mark.parametrize('send', [request_sync, request_async], ids=['sync', 'async'])
def test_post_json(scenario, lc, send):
    query = {'operationName': 'getQuestionDetail', 'variables': {'titleSlug': 'two-sum'},
             'query': 'query getQuestionDetail($titleSlug: String!) { question { title } }'}
    res, r = send(scenario, {'url': lc.base_url + '/graphql', 'method': 'POST', 'json': query,
                             'cookies': {'LEETCODE_SESSION': 'abc'}})
    assert res['status'] == 200, r.describe()
    assert json.loads(res['body'])['data']['question']['title'] == 'Two Sum'
    sent = lc.server.requests_to('graphql.getQuestionDetail')[0]
    assert json.loads(sent['body']) == query
    assert sent['headers']['content-type'] == 'application/json'


def test_post_raw_body_is_sent_exactly(scenario, lc):
    body = 'line 1\nline "2" \\ end\n'
    res, r = request_async(scenario, {'url': lc.base_url + '/problems/two-sum/submit/',
                                      'method': 'POST', 'body': body,
                                      'cookies': {'csrftoken': 'e2e-csrf'},
                                      'headers': {'X-CSRFToken': 'e2e-csrf'}})
    assert res['status'] == 200, r.describe()
    assert lc.server.requests_to('submit')[0]['body'] == body


def test_values_with_quotes_and_backslashes(scenario, lc):
    value = 'a "quoted" \\ value'
    res, r = request_sync(scenario, {'url': lc.base_url + '/api/progress/all/',
                                     'cookies': {'LEETCODE_SESSION': 'x'},
                                     'headers': {'X-Odd': value}})
    assert res['status'] == 200, r.describe()
    assert lc.server.requests_to('progress')[0]['headers']['x-odd'] == value


def test_http_error_status_is_a_response(scenario, lc):
    lc.server.override('progress', {'status': 403, 'text': 'Forbidden'})
    res, r = request_async(scenario, {'url': lc.base_url + '/api/progress/all/'})
    assert res['error'] == '' and res['status'] == 403, r.describe()
    assert res['body'] == 'Forbidden'


@pytest.mark.parametrize('send', [request_sync, request_async], ids=['sync', 'async'])
def test_connection_failure(scenario, send):
    # Port 9 (discard) on localhost: nothing listens there.
    res, r = send(scenario, {'url': 'http://127.0.0.1:9/', 'timeout': 5})
    assert res['status'] == 0, r.describe()
    assert res['error'].startswith('curl failed'), res


def test_json_helper(scenario, lc):
    s = scenario()
    s.capture('ok', 'leetcode#http#Json({"body": "{\\"a\\": [1, 2]}"})')
    s.capture('bad', 'leetcode#http#Json({"body": "<html>"})')
    r = s.run()
    r.assert_ok()
    assert r.vars['ok'] == {'a': [1, 2]}
    assert r.vars['bad'] is None


# ---- HTML -------------------------------------------------------------------

DESCRIPTION = '''<p>Given an array of integers&nbsp;<code>nums</code>&nbsp;and an integer&nbsp;<code>target</code>, return <em>indices of the two numbers such that they add up to <code>target</code></em>.</p>

<p>&nbsp;</p>
<p><strong class="example">Example 1:</strong></p>

<pre>
<strong>Input:</strong> nums = [2,7,11,15], target = 9
<strong>Output:</strong> [0,1]
</pre>

<p><img alt="tree diagram" src="https://assets.leetcode.com/x.png" style="width: 300px;" /></p>

<p><strong>Constraints:</strong></p>

<ul>
\t<li><code>2 &lt;= nums.length &lt;= 10<sup>4</sup></code></li>
\t<li><code>-10<sup>9</sup> &lt;= nums[i] &lt;= 10<sup>9</sup></code></li>
\t<li><strong>Only one valid answer exists.</strong></li>
</ul>

<p><strong>Follow-up:&nbsp;</strong>Can you come up with an algorithm that is less than <code>O(n<sup>2</sup>)</code><font face="monospace">&nbsp;</font>time complexity? &#8805; &#x2264; &amp;lt;</p>'''

EXPECTED = [
    'Given an array of integers `nums` and an integer `target`, return *indices of the two '
    'numbers such that they add up to `target`*.', '',
    '**Example 1:**', '',
    '```',
    'Input: nums = [2,7,11,15], target = 9',
    'Output: [0,1]',
    '```', '',
    '![tree diagram](https://assets.leetcode.com/x.png)', '',
    '**Constraints:**', '',
    '- `2 <= nums.length <= 10^4`',
    '- `-10^9 <= nums[i] <= 10^9`',
    '- **Only one valid answer exists.**', '',
    '**Follow-up:** Can you come up with an algorithm that is less than `O(n^2)` time '
    'complexity? ≥ ≤ &lt;',
]


def markdown(scenario, tmp_path, html):
    path = tmp_path / 'desc.html'
    path.write_text(html, 'utf-8')
    s = scenario()
    s.capture('md', 'leetcode#html#ToMarkdown(join(readfile("{}"), "\\n"), '
                    '"https://leetcode.com")'.format(path))
    r = s.run()
    r.assert_ok()
    return r.vars['md']


def test_html_description(scenario, tmp_path):
    assert markdown(scenario, tmp_path, DESCRIPTION) == EXPECTED


def test_html_lists_links_and_escapes(scenario, tmp_path):
    html = ('<p>Pick <a href="/problems/two-sum/">Two Sum</a> or 2 * 3 items:</p>'
            '<ol><li>first</li><li>second <em>one</em></li></ol>'
            '<p>Code: <code>a*b</code>, <strong> spaced </strong>.</p>')
    assert markdown(scenario, tmp_path, html) == [
        'Pick [Two Sum](https://leetcode.com/problems/two-sum/) or 2 \\* 3 items:', '',
        '1. first',
        '2. second *one*', '',
        'Code: `a*b`, **spaced** .',
    ]


def test_html_image_without_alt_text_stays_visible(scenario, tmp_path):
    """![](url) disappears entirely where Markdown is concealed."""
    assert markdown(scenario, tmp_path, '<p><img alt="" src="/x.png" /></p>') == [
        '![image](https://leetcode.com/x.png)']
