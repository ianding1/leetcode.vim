import json

try:
    from bs4 import BeautifulSoup
    import requests
    inited = 1
except ImportError:
    inited = 0


LC_BASE = 'https://leetcode.com'
LC_LOGIN = 'https://leetcode.com/accounts/login/'
LC_GRAPHQL = 'https://leetcode.com/graphql'
LC_CATEGORY_PROBLEMS = 'https://leetcode.com/api/problems/{category}'
LC_PROBLEM = 'https://leetcode.com/problems/{slug}/description'


session = None
cached_problems = []


def _make_headers():
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


def _break_code_lines(s):
    return s.replace('\r\n', '\n').replace('\xa0', ' ').split('\n')


def _break_paragraph_lines(s):
    lines = _break_code_lines(s)
    result = []
    for line in lines:
        if line.strip() != '':
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
    problems = []
    for c in categories:
        problems.extend(_get_category_problems(c))
    global cached_problems
    cached_problems = sorted(problems, key=lambda p: p['id'])
    return cached_problems


def get_problem(fid_or_slug):
    for p in cached_problems:
        if p['fid'] == fid_or_slug or p['slug'] == fid_or_slug:
            problem = p
            break
    else:
        return None

    if 'desc' in problem:
        return problem

    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=problem['slug'])
    body = {'query': '''query getQuestionDetail($titleSlug : String!) {
  question(titleSlug: $titleSlug) {
    content
    stats
    codeDefinition
    sampleTestCase
    enableRunCode
    metaData
    translatedContent
  }
}''',
            'variables': {'titleSlug': problem['slug']},
            'operationName': 'getQuestionDetail'}
    res = session.post(LC_GRAPHQL, json=body, headers=headers)
    if res.status_code != 200:
        print('cannot get the problem: {}'.format(problem['title']))
        return None

    q = res.json()['data']['question']
    soup = BeautifulSoup(q['translatedContent'] or q['content'], features='html.parser')
    problem['desc'] = _break_paragraph_lines(soup.get_text())
    problem['templates'] = {}
    for t in json.loads(q['codeDefinition']):
        problem['templates'][t['value']] = _break_code_lines(t['defaultCode'])
    problem['testable'] = q['enableRunCode']
    return problem
