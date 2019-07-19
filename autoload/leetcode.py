import json
import logging
import re
import time
from threading import Semaphore, Thread, current_thread

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
LC_PROBLEM_SET_ALL = 'https://leetcode.com/problemset/all/'


session = None
task_running = False
task_done = False
task_trigger = Semaphore(0)
task_name = ''
task_input = None
task_progress = ''
task_output = None
task_err = ''

log = logging.getLogger(__name__)
log.setLevel(logging.ERROR)

def enable_logging():
    out_hdlr = logging.FileHandler('leetcode-vim.log')
    out_hdlr.setFormatter(logging.Formatter('%(asctime)s %(message)s'))
    out_hdlr.setLevel(logging.INFO)
    log.addHandler(out_hdlr)
    log.setLevel(logging.INFO)


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
    return 'Unknown State'


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


def _remove_description(code):
    eod = code.find('[End of Description]')
    if eod == -1:
        return code
    eol = code.find('\n', eod)
    if eol == -1:
        return ''
    return code[eol+1:]


def is_login():
    return session and 'LEETCODE_SESSION' in session.cookies


def signin(username, password):
    global session
    session = requests.Session()
    res = session.get(LC_LOGIN)
    if res.status_code != 200:
        _echoerr('cannot open ' + LC_LOGIN)
        return False

    headers = {'Origin': LC_BASE,
               'Referer': LC_LOGIN}
    form = {'csrfmiddlewaretoken': session.cookies['csrftoken'],
            'login': username,
            'password': password}
    log.info('signin request: headers="%s" login="%s"', headers, username)
    # requests follows the redirect url by default
    # disable redirection explicitly
    res = session.post(LC_LOGIN, data=form, headers=headers, allow_redirects=False)
    log.info('signin response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 302:
        _echoerr('password incorrect')
        return False
    return True


def _get_category_problems(category):
    headers = _make_headers()
    url = LC_CATEGORY_PROBLEMS.format(category=category)
    res = session.get(url, headers=headers)
    if res.status_code != 200:
        _echoerr('cannot get the category: {}'.format(category))
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
    assert is_login()
    problems = []
    for c in categories:
        problems.extend(_get_category_problems(c))
    return sorted(problems, key=lambda p: p['id'])


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
    log.info('get_problem request: url="%s" headers="%s" body="%s"', LC_GRAPHQL, headers, body)
    res = session.post(LC_GRAPHQL, json=body, headers=headers)
    log.info('get_problem response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 200:
        _echoerr('cannot get the problem: {}'.format(slug))
        return None

    q = res.json()['data']['question']
    if q is None:
        _echoerr('cannot get the problem: {}'.format(slug))
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
    global task_progress
    if _in_task():
        prog_stage = 'Uploading '
        prog_bar = '.'
        task_progress = prog_stage + prog_bar

    while True:
        headers = _make_headers()
        url = LC_CHECK.format(submission=submission_id)
        log.info('check result request: url="%s" headers="%s"', url, headers)
        res = session.get(url, headers=headers)
        log.info('check result response: status="%s" body="%s"', res.status_code, res.text)
        if res.status_code != 200:
            _echoerr('cannot get the execution result')
            return None
        if _in_task():
            prog_bar += '.'

        r = res.json()
        if r['state'] == 'SUCCESS':
            prog_stage = 'Done      '
            break
        elif r['state'] == 'PENDING':
            prog_stage = 'Pending   '
        elif r['state'] == 'STARTED':
            prog_stage = 'Running   '
        if _in_task():
            task_progress = prog_stage + prog_bar

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
        result['answer'] = _split(r.get('code_output', ''))
        result['expected_answer'] = _split(r.get('expected_output', ''))
        result['stdout'] = _split(r.get('std_output', ''))
        result['runtime_percentile'] = r.get('runtime_percentile', '')
    else:
        result['stdout'] = r.get('code_output', [])
        result['expected_answer'] = []
        result['runtime_percentile'] = r.get('runtime_percentile', '')
    return result


def test_solution(slug, filetype, code=None):
    assert is_login()
    problem = get_problem(slug)
    if not problem:
        return None

    if not problem['testable']:
        _echoerr('the problem is not testable, please submit directly')
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
    url = LC_TEST.format(slug=slug)
    log.info('test solution request: url="%s" headers="%s" body="%s"', url, headers, body)
    res = session.post(url, json=body, headers=headers)
    log.info('test solution response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 200:
        if 'too fast' in res.text:
            _echoerr('you are sending the request too fast')
        else:
            _echoerr('cannot test the solution for ' + slug)
        return None

    actual = _check_result(res.json()['interpret_id'])
    expected = _check_result(res.json()['interpret_expected_id'])
    actual['testcase'] = problem['testcase'].split('\n')
    actual['expected_answer'] = expected['answer']
    actual['title'] = problem['title']
    return actual


def test_solution_async(slug, filetype, code=None):
    assert is_login()
    global task_input, task_name
    if task_running:
        _echoerr('there is other task running: ' + task_name)
        return False

    if code is None:
        code = '\n'.join(vim.current.buffer)
    code = _remove_description(code)

    task_name = 'test_solution'
    task_input = [slug, filetype, code]
    task_trigger.release()
    return True


def submit_solution(slug, filetype, code=None):
    assert is_login()
    problem = get_problem(slug)
    if not problem:
        return None

    if code is None:
        code = '\n'.join(vim.current.buffer)
    code = _remove_description(code)

    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    body = {'data_input': problem['testcase'],
            'lang': filetype,
            'question_id': str(problem['id']),
            'test_mode': False,
            'typed_code': code,
            'judge_type': 'large'}
    url = LC_SUBMIT.format(slug=slug)
    log.info('submit solution request: url="%s" headers="%s" body="%s"', url, headers, body)
    res = session.post(url, json=body, headers=headers)
    log.info('submit solution response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 200:
        if 'too fast' in res.text:
            _echoerr('you are sending the request too fast')
        else:
            _echoerr('cannot submit the solution for ' + slug)
        return None

    result = _check_result(res.json()['submission_id'])
    result['title'] = problem['title']
    return result


def submit_solution_async(slug, filetype, code=None):
    assert is_login()
    global task_input, task_name
    if task_running:
        _echoerr('there is other task running: ' + task_name)
        return False

    if code is None:
        code = '\n'.join(vim.current.buffer)

    task_name = 'submit_solution'
    task_input = [slug, filetype, code]
    task_trigger.release()
    return True


def get_submissions(slug):
    assert is_login()
    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    url = LC_SUBMISSIONS.format(slug=slug)
    log.info('get submissions request: url="%s" headers="%s"', url, headers)
    res = session.get(url, headers=headers)
    log.info('get submissions response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 200:
        _echoerr('cannot find the submissions of problem: ' + slug)
        return None
    submissions = []
    for r in res.json()['submissions_dump']:
        s = {
            'id': r['url'].split('/')[3],
            'time': r['time'].replace('\xa0', ' '),
            'status': r['status_display'],
            'runtime': r['runtime'],
        }
        submissions.append(s)
    return submissions


def _group1(match, default):
    if match:
        return match.group(1)
    return default


def _unescape(s):
    return s.encode().decode('unicode_escape')


def get_submission(sid):
    assert is_login()
    headers = _make_headers()
    url = LC_SUBMISSION.format(submission=sid)
    log.info('get submission request: url="%s" headers="%s"', url, headers)
    res = session.get(url, headers=headers)
    log.info('get submission response: status="%s" body="%s"', res.status_code, res.text)
    if res.status_code != 200:
        _echoerr('cannot find the submission: ' + sid)
        return None

    # we need to parse the data from the Javascript snippet
    s = res.text
    submission = {
        'id': sid,
        'state': _status_to_name(int(_group1(re.search(r"status_code: parseInt\('([^']*)'", s),
                                             'not found'))),
        'runtime': _group1(re.search("runtime: '([^']*)'", s), 'not found'),
        'passed': _group1(re.search("total_correct : '([^']*)'", s), 'not found'),
        'total': _group1(re.search("total_testcases : '([^']*)'", s), 'not found'),
        'testcase': _split(_unescape(_group1(re.search("input : '([^']*)'", s), ''))),
        'answer': _split(_unescape(_group1(re.search("code_output : '([^']*)'", s), ''))),
        'expected_answer': _split(_unescape(_group1(re.search("expected_output : '([^']*)'", s),
                                                    ''))),
        'problem_id': _group1(re.search("questionId: '([^']*)'", s), 'not found'),
        'slug': _group1(re.search("editCodeUrl: '([^']*)'", s), '///').split('/')[2],
        'filetype': _group1(re.search("getLangDisplay: '([^']*)'", s), 'not found'),
        'error': [],
        'stdout': [],
    }

    problem = get_problem(submission['slug'])
    submission['title'] = problem['title']

    # the punctuations and newlines in the code are escaped like '\\u0010' ('\\' => real backslash)
    # to unscape the string, we do the trick '\\u0010'.encode().decode('unicode_escape') ==> '\n'
    submission['code'] = _break_code_lines(_unescape(_group1(re.search("submissionCode: '([^']*)'", s), '')))

    dist_str = _unescape(_group1(re.search("runtimeDistributionFormatted: '([^']*)'", s),
                                 '{"distribution":[]}'))
    dist = json.loads(dist_str)['distribution']
    dist.reverse()

    # the second key "runtime" is the runtime in milliseconds
    # we need to search from the position after the first "runtime" key
    prev_runtime = re.search("runtime: '([^']*)'", s)
    if not prev_runtime:
        my_runtime = 0
    else:
        my_runtime = int(_group1(re.search("runtime: '([^']*)'", s[prev_runtime.end():]), 0))

    accum = 0
    for runtime, frequency in dist:
        accum += frequency
        if my_runtime >= int(runtime):
            break

    submission['runtime_percentile'] = '{:.1f}%'.format(accum)
    return submission


def _process_topic_element(topic):
    return {'topic_name': topic.find(class_='text-gray').string.strip(),
            'num_problems': topic.find(class_='badge').string,
            'topic_slug': topic.get('href').split('/')[2]}


def _process_company_element(company):
    return {'company_name': company.find(class_='text-gray').string.strip(),
            'num_problems': company.find(class_='badge').string,
            'company_slug': company.get('href').split('/')[2]}


def get_topics_and_companies():
    headers = _make_headers()
    log.info('get_topics_and_companies request: url="%s', LC_PROBLEM_SET_ALL)
    res = session.get(LC_PROBLEM_SET_ALL, headers=headers)
    log.info('get_topics_and_companies response: status="%s" body="%s"', res.status_code,
             res.text)

    if res.status_code != 200:
        _echoerr('cannot get topics')
        return []

    soup = BeautifulSoup(res.text, features='html.parser')

    topic_elements = soup.find_all(class_='sm-topic')
    topics = [_process_topic_element(topic) for topic in topic_elements]

    company_elements = soup.find_all(class_='sm-company')
    companies = [_process_company_element(company) for company in company_elements]

    return {
        'topics': topics,
        'companies': companies
        }


def get_problems_of_topic(topic_slug):
    request_body = {
        'operationName':'getTopicTag',
        'variables': {'slug': topic_slug},
        'query': 'query getTopicTag($slug: String!) {\n  topicTag(slug: $slug) {\n    name\n    translatedName\n    questions {\n      status\n      questionId\n      questionFrontendId\n      title\n      titleSlug\n      translatedTitle\n      stats\n      difficulty\n      isPaidOnly\n      topicTags {\n        name\n        translatedName\n        slug\n        __typename\n      }\n      companyTags {\n        name\n        translatedName\n        slug\n        __typename\n      }\n      __typename\n    }\n    frequencies\n    __typename\n  }\n  favoritesLists {\n    publicFavorites {\n      ...favoriteFields\n      __typename\n    }\n    privateFavorites {\n      ...favoriteFields\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment favoriteFields on FavoriteNode {\n  idHash\n  id\n  name\n  isPublicFavorite\n  viewCount\n  creator\n  isWatched\n  questions {\n    questionId\n    title\n    titleSlug\n    __typename\n  }\n  __typename\n}\n'}

    headers = _make_headers()

    log.info('get_problems_of_topic request: headers="%s" body="%s"', headers,
             request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)

    log.info('get_problems_of_topic response: status="%s" body="%s"',
             res.status_code, res.text)

    if res.status_code != 200:
        _echoerr('cannot get problems of the topic')
        return

    topic_tag = res.json()['data']['topicTag']

    def process_problem(p):
        stats = json.loads(p['stats'])

        return {
            'state': _state_to_flag(p['status']),
            'id': p['questionId'],
            'fid': p['questionFrontendId'],
            'title': p['title'],
            'slug': p['titleSlug'],
            'paid_only': p['isPaidOnly'],
            'ac_rate': stats['totalAcceptedRaw'] / stats['totalSubmissionRaw'],
            'level': p['difficulty'],
            'favor': False}

    return {
        'topic_name': topic_tag['name'],
        'problems': [process_problem(p) for p in topic_tag['questions']]}


def get_problems_of_company(company_slug):
    request_body = {
        'operationName':'getCompanyTag',
        'variables': {'slug': company_slug},
        'query': 'query getCompanyTag($slug: String!) {\n  companyTag(slug: $slug) {\n    name\n    translatedName\n    frequencies\n    questions {\n      ...questionFields\n      __typename\n    }\n    __typename\n  }\n  favoritesLists {\n    publicFavorites {\n      ...favoriteFields\n      __typename\n    }\n    privateFavorites {\n      ...favoriteFields\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment favoriteFields on FavoriteNode {\n  idHash\n  id\n  name\n  isPublicFavorite\n  viewCount\n  creator\n  isWatched\n  questions {\n    questionId\n    title\n    titleSlug\n    __typename\n  }\n  __typename\n}\n\nfragment questionFields on QuestionNode {\n  status\n  questionId\n  questionFrontendId\n  title\n  titleSlug\n  translatedTitle\n  stats\n  difficulty\n  isPaidOnly\n  topicTags {\n    name\n    translatedName\n    slug\n    __typename\n  }\n  frequencyTimePeriod\n  __typename\n}\n'}

    headers = _make_headers()
    headers['Referer'] = 'https://leetcode.com/company/{}/'.format(company_slug)

    log.info('get_problems_of_company request: headers="%s" body="%s"', headers,
             request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)

    log.info('get_problems_of_company response: status="%s" body="%s"',
             res.status_code, res.text)

    if res.status_code != 200:
        _echoerr('cannot get problems of the company')
        return

    company_tag = res.json()['data']['companyTag']

    def process_problem(p):
        stats = json.loads(p['stats'])

        return {
            'state': _state_to_flag(p['status']),
            'id': p['questionId'],
            'fid': p['questionFrontendId'],
            'title': p['title'],
            'slug': p['titleSlug'],
            'paid_only': p['isPaidOnly'],
            'ac_rate': stats['totalAcceptedRaw'] / stats['totalSubmissionRaw'],
            'level': p['difficulty'],
            'favor': False}

    return {
        'company_name': company_tag['name'],
        'problems': [process_problem(p) for p in company_tag['questions']]}


def _thread_main():
    global task_running, task_done, task_output, task_err
    while True:
        task_trigger.acquire()
        task_running = True
        task_done = False
        task_output = None
        task_err = ''

        log.info('task thread input: name="%s" input="%s"', task_name, task_input)
        try:
            if task_name == 'test_solution':
                slug, file_type, code = task_input
                task_output = test_solution(slug, file_type, code)
            elif task_name == 'submit_solution':
                slug, file_type, code = task_input
                task_output = submit_solution(slug, file_type, code)
        except BaseException as e:
            task_err = str(e)
        log.info('task thread output: name="%s" output="%s" error="%s"', task_name, task_output,
                 task_err)
        task_running = False
        task_done = True


def _in_task():
    return current_thread() == task_thread


def _echoerr(s):
    global task_err
    if _in_task():
        task_err = s
    else:
        print(s)


task_thread = Thread(target=_thread_main, daemon=True)
task_thread.start()
