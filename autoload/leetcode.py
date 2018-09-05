import json
import time

try:
    from bs4 import BeautifulSoup
    import requests
    inited = 1
except ImportError:
    inited = 0

try:
    import vim
except ImportError:
    vim = None


LC_BASE = 'https://leetcode.com'
LC_LOGIN = 'https://leetcode.com/accounts/login/'
LC_GRAPHQL = 'https://leetcode.com/graphql'
LC_CATEGORY_PROBLEMS = 'https://leetcode.com/api/problems/{category}'
LC_PROBLEM = 'https://leetcode.com/problems/{slug}/description'
LC_TEST = 'https://leetcode.com/problems/{slug}/interpret_solution/'
LC_SUBMIT = 'https://leetcode.com/problems/{slug}/submit/'
LC_SUBMISSIONS = 'https://leetcode.com/api/submissions/{slug}'
LC_SUBMISSION = 'https://leetcode.com/submissions/detail/{submission}/'
LC_CHECK = 'https://leetcode.com/submissions/detail/{submission}/check/'


session = None
problem_list = []
problem_list_categories = []


def _make_headers():
    assert is_login()
    headers = {'Origin': LC_BASE,
               'Referer': LC_BASE,
               'X-CSRFToken': session.cookies['csrftoken'],
               'X-Requested-With': 'XMLHttpRequest'}
    return headers


def _level_to_name(level):
    if level == 1:
        return 'Easy'
    if level == 2:
        return 'Medium'
    if level == 3:
        return 'Hard'
    return ' '


def _state_to_flag(state):
    if state == 'ac':
        return 'X'
    elif state == 'notac':
        return '?'
    return ' '


def _status_to_name(status):
    if status == 10:
        return 'Accepted'
    if status == 11:
        return 'Wrong Answer'
    if status == 12:
        return 'Memory Limit Exceeded'
    if status == 13:
        return 'Output Limit Exceeded'
    if status == 14:
        return 'Time Limit Exceeded'
    if status == 15:
        return 'Runtime Error'
    if status == 16:
        return 'Internal Error'
    if status == 20:
        return 'Compile Error'
    if status == 21:
        return 'Unknown Error'
    return 'Unknown'


def _break_code_lines(s):
    return s.replace('\r\n', '\n').replace('\xa0', ' ').split('\n')


def _break_paragraph_lines(s):
    lines = _break_code_lines(s)
    result = []
    # reserve one and only one empty line between two non-empty lines
    for line in lines:
        if line.strip() != '':  # a line with only whitespaces is also empty
            result.append(line)
            result.append('')
    return result


def is_login():
    return session and 'LEETCODE_SESSION' in session.cookies


def signin(username, password):
    global session
    session = requests.Session()
    res = session.get(LC_LOGIN)
    if res.status_code != 200:
        print('cannot open ' + LC_LOGIN)
        return False

    headers = {'Origin': LC_BASE,
               'Referer': LC_LOGIN}
    form = {'csrfmiddlewaretoken': session.cookies['csrftoken'],
            'login': username,
            'password': password}
    # requests follows the redirect url by default
    # disable redirection explicitly
    res = session.post(LC_LOGIN, data=form, headers=headers, allow_redirects=False)
    if res.status_code != 302:
        print('password incorrect')
        return False
    return True


def _get_category_problems(category):
    headers = _make_headers()
    url = LC_CATEGORY_PROBLEMS.format(category=category)
    res = session.get(url, headers=headers)
    if res.status_code != 200:
        print('cannot get the category: {}'.format(category))
        return []

    problems = []
    content = res.json()
    for p in content['stat_status_pairs']:
        # skip hidden questions
        if p['stat']['question__hide']:
            continue
        problem = {'state': _state_to_flag(p['status']),
                   'id': p['stat']['question_id'],
                   'fid': p['stat']['frontend_question_id'],
                   'title': p['stat']['question__title'],
                   'slug': p['stat']['question__title_slug'],
                   'paid_only': p['paid_only'],
                   'ac_rate': p['stat']['total_acs'] / p['stat']['total_submitted'],
                   'level': _level_to_name(p['difficulty']['level']),
                   'favor': p['is_favor'],
                   'category': content['category_slug']}
        problems.append(problem)
    return problems


def get_problems(categories):
    global problem_list, problem_list_categories
    assert is_login()
    # check for the cached result first
    if categories == problem_list_categories:
        return problem_list

    problems = []
    for c in categories:
        problems.extend(_get_category_problems(c))
    problem_list = sorted(problems, key=lambda p: p['id'])
    problem_list_categories = categories
    return problem_list


def get_problem(slug):
    assert is_login()
    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    body = {'query': '''query getQuestionDetail($titleSlug : String!) {
  question(titleSlug: $titleSlug) {
    questionId
    title
    content
    stats
    difficulty
    codeDefinition
    sampleTestCase
    enableRunCode
    translatedContent
  }
}''',
            'variables': {'titleSlug': slug},
            'operationName': 'getQuestionDetail'}
    res = session.post(LC_GRAPHQL, json=body, headers=headers)
    if res.status_code != 200:
        print('cannot get the problem: {}'.format(slug))
        print(res.text)
        return None

    q = res.json()['data']['question']
    if q is None:
        print('cannot get the problem: {}'.format(slug))
        print(res.text)
        return None

    soup = BeautifulSoup(q['translatedContent'] or q['content'], features='html.parser')
    problem = {}
    problem['id'] = q['questionId']
    problem['title'] = q['title']
    problem['slug'] = slug
    problem['level'] = q['difficulty']
    problem['desc'] = _break_paragraph_lines(soup.get_text())
    problem['templates'] = {}
    for t in json.loads(q['codeDefinition']):
        problem['templates'][t['value']] = _break_code_lines(t['defaultCode'])
    problem['testable'] = q['enableRunCode']
    problem['testcase'] = q['sampleTestCase']
    stats = json.loads(q['stats'])
    problem['total_accepted'] = stats['totalAccepted']
    problem['total_submission'] = stats['totalSubmission']
    problem['ac_rate'] = stats['acRate']
    return problem


def _split(s):
    # str.split has an disadvantage that ''.split('\n') results in [''], but what we want
    # is []. This small function returns [] if `s` is a blank string, that is, containing no
    # characters other than whitespaces.
    if s.strip() == '':
        return []
    return s.split('\n')


def _check_result(submission_id):
    while True:
        headers = _make_headers()
        res = session.get(LC_CHECK.format(submission=submission_id), headers=headers)
        if res.status_code != 200:
            print('cannot get the execution result')
            return None
        r = res.json()
        if r['state'] == 'SUCCESS':
            break
        time.sleep(1)

    result = {
        'answer': r.get('code_answer', []),
        'runtime': r['status_runtime'],
        'state': _status_to_name(r['status_code']),
        'testcase': _split(r.get('input', r.get('last_testcase', ''))),
        'passed': r.get('total_correct') or 0,
        'total': r.get('total_testcases') or 0,
        'error': [v for k, v in r.items() if 'error' in k and v]
    }

    # the keys differs between the result of testing the code and submitting it
    # for submission judge_type is 'large', and for testing judge_type does not exist
    if r.get('judge_type') == 'large':
        result['answer'] = _split(result.get('code_output', ''))
        result['expected_answer'] = _split(result.get('expected_output', ''))
        result['stdout'] = _split(result.get('std_output', ''))
    else:
        result['stdout'] = result.get('code_output', [])
        result['expected_answer'] = []
    return result


def test_solution(slug, filetype, code=None):
    assert is_login()
    problem = get_problem(slug)
    if not problem:
        return None

    if code is None:
        code = '\n'.join(vim.current.buffer)

    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    body = {'data_input': problem['testcase'],
            'lang': filetype,
            'question_id': str(problem['id']),
            'test_mode': False,
            'typed_code': code}
    res = session.post(LC_TEST.format(slug=slug), json=body, headers=headers)
    if res.status_code != 200:
        if 'too soon' in res.text:
            print('you submitted the code too soon')
        else:
            print('cannot test the solution for ' + slug)
        return None

    actual = _check_result(res.json()['interpret_id'])
    expected = _check_result(res.json()['interpret_expected_id'])
    actual['testcase'] = problem['testcase'].split('\n')
    actual['expected_answer'] = expected['answer']
    return actual


def submit_solution(slug, filetype, code=None):
    assert is_login()
    problem = get_problem(slug)
    if not problem:
        return None

    if code is None:
        code = '\n'.join(vim.current.buffer)

    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    body = {'data_input': problem['testcase'],
            'lang': filetype,
            'question_id': str(problem['id']),
            'test_mode': False,
            'typed_code': code,
            'judge_type': 'large'}
    res = session.post(LC_SUBMIT.format(slug=slug), json=body, headers=headers)
    if res.status_code != 200:
        if 'too soon' in res.text:
            print('you submitted the code too soon')
        else:
            print('cannot submit the solution for ' + slug)
        return None

    return _check_result(res.json()['submission_id'])
