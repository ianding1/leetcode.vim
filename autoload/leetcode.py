import json
import logging
import time
import os
import pickle
from threading import Semaphore, Thread, current_thread

try:
    import requests
    inited = 1
    import_error = ''
except ImportError as e:
    inited = 0
    import_error = str(e)

try:
    import vim
except ImportError:
    vim = None

try:
    import browser_cookie3
except ImportError:
    browser_cookie3 = None

try:
    import keyring
except ImportError:
    keyring = None


LC_BASE = os.environ['LEETCODE_BASE_URL']
LC_LOGIN = LC_BASE + '/accounts/login/'
LC_GRAPHQL = LC_BASE + '/graphql'
LC_CATEGORY_PROBLEMS = LC_BASE + '/api/problems/{category}/'
LC_PROBLEM = LC_BASE + '/problems/{slug}/description'
LC_TEST = LC_BASE + '/problems/{slug}/interpret_solution/'
LC_SUBMIT = LC_BASE + '/problems/{slug}/submit/'
LC_SUBMISSIONS = LC_BASE + '/api/submissions/{slug}/'
LC_SUBMISSION = LC_BASE + '/submissions/detail/{submission}/'
LC_CHECK = LC_BASE + '/submissions/detail/{submission}/check/'
LC_PROGRESS_ALL = LC_BASE + '/api/progress/all/'

EMPTY_FREQUENCIES = [0, 0, 0, 0, 0, 0, 0, 0]

# Requests without a browser-like User-Agent have been reported to get 403s
# from LeetCode (PRs #77, #83).
USER_AGENT = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36')

# Give up waiting for the judge after this many seconds.
CHECK_TIMEOUT = 120

# Cookies needed to act as the signed-in user.
SESSION_COOKIES = ('LEETCODE_SESSION', 'csrftoken')

session = None
# See _refresh_csrf_token().
csrf_token = ''
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
               'User-Agent': USER_AGENT,
               'X-Requested-With': 'XMLHttpRequest',
               'X-CSRFToken': csrf_token}
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
    if state == 'notac':
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


def _format_percentile(p):
    """'95.5' for 95.5; '' when unknown. Formatted here because Neovim turns
    a whole float like 100.0 into the Number 100 on its way to Vim script."""
    if p is None or p == '':
        return ''
    try:
        return '{:.1f}'.format(float(p))
    except (TypeError, ValueError):
        return str(p)


def _break_code_lines(s):
    return s.replace('\r\n', '\n').replace('\xa0', ' ').split('\n')


def _similar_questions(text):
    try:
        similar = json.loads(text or '[]')
        return [{'title': p.get('translatedTitle') or p['title'], 'slug': p['titleSlug'],
                 'level': p.get('difficulty', '')} for p in similar]
    except (KeyError, TypeError, ValueError):
        return []


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


def get_progress():
    headers = _make_headers()
    res = session.get(LC_PROGRESS_ALL, headers=headers)
    if res.status_code != 200:
        _echoerr('cannot get the progress')
        return None

    data = res.json()
    if 'solvedTotal' not in data:
        return None
    return data


def _start_session(cookies):
    global session
    session = requests.Session()
    # Only the session is kept; the CSRF token is fetched.
    for cookie in cookies:
        if cookie.name == 'LEETCODE_SESSION':
            session.cookies.set_cookie(cookie)
    if get_progress() is None:
        # Don't leave rejected cookies behind as if signed in.
        session = None
        return False
    _refresh_csrf_token()
    return True


def _refresh_csrf_token():
    """LeetCode refuses test runs and submissions without a current CSRF
    token: a csrftoken cookie, repeated in the X-CSRFToken header (HTTP 499
    when it is missing or stale). It isn't tied to the session, and LeetCode
    hands one out with any page, so the plugin gets its own instead of asking
    for it, and gets a new one when LeetCode turns it down."""
    global csrf_token
    try:
        res = requests.get(LC_GRAPHQL, headers={'User-Agent': USER_AGENT}, timeout=30)
        token = res.cookies.get('csrftoken')
    except requests.RequestException:
        token = None
    if not token:
        return False
    for cookie in [c for c in session.cookies if c.name == 'csrftoken']:
        session.cookies.clear(cookie.domain, cookie.path, cookie.name)
    session.cookies.set('csrftoken', token)
    csrf_token = token
    return True


def _post_to_judge(url, body, referer):
    """POST a test run or submission, once more with a new CSRF token if
    LeetCode turns the token down."""
    for attempt in range(2):
        headers = _make_headers()
        headers['Referer'] = referer
        log.info('judge request: url="%s" headers="%s" body="%s"', url, headers, body)
        res = session.post(url, json=body, headers=headers)
        log.info('judge response: status="%s" body="%s"', res.status_code, res.text)
        if res.status_code != 499 or attempt or not _refresh_csrf_token():
            return res


def start_session_with_cookies(cookies):
    """Sign in with {name: value} cookies; True if LeetCode accepts them."""
    jar = [requests.cookies.create_cookie(name, value)
           for name, value in cookies.items() if value]
    return _start_session(jar)


def _cookies_from_env():
    """The session cookie from $LEETCODE_SESSION."""
    value = os.environ.get('LEETCODE_SESSION')
    return [requests.cookies.create_cookie('LEETCODE_SESSION', value)] if value else []


def load_session_cookie(browser):
    if browser == 'env':
        cookies = _cookies_from_env()
        if not any(c.name == 'LEETCODE_SESSION' for c in cookies):
            _echoerr('$LEETCODE_SESSION is not set. Copy the LEETCODE_SESSION cookie from '
                     'your browser into it.')
            return False
        if not _start_session(cookies):
            _echoerr('cannot get progress. Please update $LEETCODE_SESSION.')
            return False
        return True

    if browser_cookie3 is None:
        _echoerr('browser_cookie3 not installed: pip3 install browser_cookie3 --user')
        return False
    if keyring is None:
        _echoerr('keyring not installed: pip3 install keyring --user')
        return False

    cookies = None
    cached = keyring.get_password('leetcode.vim', 'SESSION_COOKIE')
    if cached is not None:
        cookies = pickle.loads(cached.encode('utf-8'))
        if not isinstance(cookies, list):  # cached by an older version
            cookies = [cookies]
        if any(c.is_expired() for c in cookies):
            cookies = None

    if cookies is None:
        jar = getattr(browser_cookie3, browser)(domain_name=LC_BASE.split('/')[-1])
        cookies = [c for c in jar if c.name in SESSION_COOKIES]
        if not any(c.name == 'LEETCODE_SESSION' for c in cookies):
            _echoerr('Leetcode session cookie not found. Please login in browser.')
            return False
        keyring.set_password('leetcode.vim', 'SESSION_COOKIE',
                             pickle.dumps(cookies, protocol=0).decode('utf-8'))

    if not _start_session(cookies):
        _echoerr('cannot get progress. Please relogin in your browser.')
        keyring.delete_password('leetcode.vim', 'SESSION_COOKIE')
        return False

    return True


def _get_category_problems(category):
    headers = _make_headers()
    url = LC_CATEGORY_PROBLEMS.format(category=category)
    log.info('_get_category_problems request: url="%s" headers="%s"',
             url, headers)
    res = session.get(url, headers=headers)
    log.info('_get_category_problems response: status="%s" body="%s"',
             res.status_code, res.text)
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
                   'category': content['category_slug'],
                   'frequency': p['frequency']}
        problems.append(problem)
    return problems


def get_problems(categories):
    assert is_login()
    problems = []
    for c in categories:
        problems.extend(_get_category_problems(c))
    return sorted(problems, key=lambda p: p['id'])


def _split(s):
    if isinstance(s, list):
        lines = []
        for element in s:
            lines.extend(_split(element))
        return lines

    # Replace all \r\n to \n and all \r (alone) to \n
    s = s.replace('\r\n', '\n').replace('\r', '\n').replace('\0', '\n')
    # str.split has an disadvantage that ''.split('\n') results in [''], but what we want
    # is []. This small function returns [] if `s` is a blank string, that is, containing no
    # characters other than whitespaces.
    if s.strip() == '':
        return []
    return s.split('\n')


def get_problem(slug):
    assert is_login()
    headers = _make_headers()
    headers['Referer'] = LC_PROBLEM.format(slug=slug)
    body = {'query': '''query getQuestionDetail($titleSlug : String!) {
  question(titleSlug: $titleSlug) {
    questionId
    questionFrontendId
    title
    content
    stats
    difficulty
    codeDefinition
    sampleTestCase
    enableRunCode
    translatedContent
    likes
    dislikes
    topicTags {
      name
      translatedName
    }
    hints
    similarQuestions
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
    content = q['translatedContent'] or q['content']
    if content is None:
        _echoerr('cannot get the problem: {}'.format(slug))
        return None

    problem = {}
    problem['id'] = q['questionId']
    problem['fid'] = q['questionFrontendId']
    problem['title'] = q['title']
    problem['slug'] = slug
    problem['level'] = q['difficulty']
    problem['content'] = content
    problem['likes'] = q.get('likes') or 0
    problem['dislikes'] = q.get('dislikes') or 0
    problem['topics'] = [t.get('translatedName') or t['name'] for t in q.get('topicTags') or []]
    problem['hints'] = q.get('hints') or []
    problem['similar'] = _similar_questions(q.get('similarQuestions'))
    problem['templates'] = {}
    for t in json.loads(q['codeDefinition']):
        problem['templates'][t['value']] = _break_code_lines(t['defaultCode'])
    problem['testable'] = q['enableRunCode']
    problem['testcase'] = _split(q['sampleTestCase'])
    stats = json.loads(q['stats'])
    problem['total_accepted'] = stats['totalAccepted']
    problem['total_submission'] = stats['totalSubmission']
    problem['ac_rate'] = stats['acRate']
    return problem


def _response_error(res, default):
    """The judge's own error message if the response carries one."""
    if 'too fast' in res.text:
        return 'you are sending the request too fast'
    try:
        data = res.json()
    except ValueError:
        data = None
    if isinstance(data, dict) and data.get('error'):
        return str(data['error'])
    return default if res.status_code == 200 else '{} (HTTP {})'.format(default, res.status_code)


def _json_field(res, key):
    """res.json()[key] for a successful JSON response, else None."""
    if res.status_code != 200:
        return None
    try:
        data = res.json()
    except ValueError:
        return None
    return data.get(key) if isinstance(data, dict) else None


def _check_result(submission_id, is_submit):
    global task_progress
    prog_stage = 'Uploading '
    prog_bar = '.'
    if _in_task():
        task_progress = prog_stage + prog_bar

    deadline = time.time() + CHECK_TIMEOUT
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
        state = r.get('state')
        if state == 'SUCCESS':
            prog_stage = 'Done      '
            break
        elif state == 'PENDING':
            prog_stage = 'Pending   '
        elif state == 'STARTED':
            prog_stage = 'Running   '
        else:
            _echoerr('unexpected judge state: {}'.format(state))
            return None
        if _in_task():
            task_progress = prog_stage + prog_bar

        if time.time() > deadline:
            _echoerr('gave up waiting for the judge after {}s'.format(CHECK_TIMEOUT))
            return None
        time.sleep(1)

    result = {
        'answer': r.get('code_answer', []),
        'runtime': r['status_runtime'],
        'state': _status_to_name(r['status_code']),
        'testcase': _split(r.get('input', r.get('last_testcase', ''))),
        'passed': r.get('total_correct') or 0,
        'total': r.get('total_testcases') or 0,
        'error': _split([v for k, v in r.items() if 'error' in k and v]),
        'memory': r.get('status_memory') or '',
        'memory_percentile': _format_percentile(r.get('memory_percentile')),
    }

    # The keys differ between the result of testing the code and submitting it.
    # The caller knows which one it asked for; don't guess from the response.
    if is_submit:
        result['answer'] = _split(r.get('code_output', ''))
        result['expected_answer'] = _split(r.get('expected_output', ''))
        result['stdout'] = _split(r.get('std_output', ''))
        result['runtime_percentile'] = _format_percentile(r.get('runtime_percentile'))
    else:
        # Test states cannot distinguish accepted answers from wrong answers.
        if result['state'] == 'Accepted':
            result['state'] = 'Finished'
        result['stdout'] = _split(r.get('code_output', []))
        result['runtime_percentile'] = _format_percentile(r.get('runtime_percentile'))
        result['expected_answer'] = r.get('expected_code_answer', [])
        # The judge's verdict on the answers, when it gives one.
        result['correct_answer'] = r.get('correct_answer')
    return result


def test_solution(problem_id, title, slug, filetype, code, test_input):
    assert is_login()

    code = _remove_description(code)

    body = {'data_input': test_input,
            'lang': filetype,
            'question_id': str(problem_id),
            'test_mode': False,
            'typed_code': code}
    res = _post_to_judge(LC_TEST.format(slug=slug), body, LC_PROBLEM.format(slug=slug))
    interpret_id = _json_field(res, 'interpret_id')
    if not interpret_id:
        _echoerr(_response_error(res, 'cannot test the solution for ' + slug))
        return None

    result = _check_result(interpret_id, is_submit=False)
    if result is None:
        return None
    result['testcase'] = test_input.split('\n')
    result['title'] = title
    return result


def test_solution_async(problem_id, title, slug, filetype, code, test_input):
    assert is_login()
    global task_input, task_name
    if task_running:
        _echoerr('there is other task running: ' + task_name)
        return False

    code = _remove_description(code)

    task_name = 'test_solution'
    task_input = [problem_id, title, slug, filetype, code, test_input]
    _start_task()
    return True


def submit_solution(slug, filetype, code=None):
    assert is_login()
    problem = get_problem(slug)
    if not problem:
        return None

    if code is None:
        code = '\n'.join(vim.current.buffer)
    code = _remove_description(code)

    body = {'data_input': problem['testcase'],
            'lang': filetype,
            'question_id': str(problem['id']),
            'test_mode': False,
            'typed_code': code,
            'judge_type': 'large'}
    res = _post_to_judge(LC_SUBMIT.format(slug=slug), body, LC_PROBLEM.format(slug=slug))
    submission_id = _json_field(res, 'submission_id')
    if not submission_id:
        _echoerr(_response_error(res, 'cannot submit the solution for ' + slug))
        return None

    result = _check_result(submission_id, is_submit=True)
    if result is None:
        return None
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
    _start_task()
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
            'lang': r.get('lang_name') or r.get('lang') or '',
            'memory': r.get('memory') or '',
        }
        submissions.append(s)
    return submissions


def get_submission(sid):
    assert is_login()
    request_body = {
        'operationName': 'submissionDetails',
        'variables': {'submissionId': int(sid)},
        'query': '''query submissionDetails($submissionId: Int!) {
  submissionDetails(submissionId: $submissionId) {
    runtimeDisplay
    runtimePercentile
    memoryDisplay
    memoryPercentile
    code
    statusCode
    totalCorrect
    totalTestcases
    lastTestcase
    codeOutput
    expectedOutput
    runtimeError
    compileError
    lang {
      name
    }
    question {
      questionId
      titleSlug
    }
  }
}
'''}

    headers = _make_headers()
    headers['Referer'] = LC_SUBMISSION.format(submission=sid)
    log.info('get submission request: headers="%s" body="%s"', headers, request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)
    log.info('get submission response: status="%s" body="%s"', res.status_code, res.text)
    try:
        detail = res.json()['data']['submissionDetails'] if res.status_code == 200 else None
    except (KeyError, TypeError, ValueError):
        detail = None
    if not detail:
        _echoerr('cannot find the submission: ' + sid)
        return None

    def text(key):
        return detail.get(key) or ''

    error = text('compileError') or text('runtimeError')
    submission = {
        'id': sid,
        'state': _status_to_name(detail.get('statusCode')),
        'runtime': text('runtimeDisplay') or 'N/A',
        'passed': str(detail.get('totalCorrect')),
        'total': str(detail.get('totalTestcases')),
        'testcase': _split(text('lastTestcase')),
        'answer': _split(text('codeOutput')),
        'expected_answer': _split(text('expectedOutput')),
        'problem_id': detail['question']['questionId'],
        'slug': detail['question']['titleSlug'],
        'filetype': detail['lang']['name'],
        'error': _split(error) if error else [],
        'stdout': [],
        'code': (detail.get('code') or '').splitlines(),
        'runtime_percentile': _format_percentile(detail.get('runtimePercentile')),
        'memory': text('memoryDisplay'),
        'memory_percentile': _format_percentile(detail.get('memoryPercentile')),
    }

    problem = get_problem(submission['slug'])
    if problem is None:
        return None
    submission['title'] = problem['title']
    return submission


def get_topics_and_companies():
    request_body = {
        'operationName': 'getTopicsAndCompanies',
        'variables': {},
        'query': '''query getTopicsAndCompanies {
  questionTopicTags {
    edges {
      node {
        name
        translatedName
        slug
        questionIds
      }
    }
  }
  companyTags {
    name
    slug
    questionCount
  }
}
'''}

    headers = _make_headers()
    log.info('get_topics_and_companies request: headers="%s" body="%s"', headers, request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)
    log.info('get_topics_and_companies response: status="%s" body="%s"', res.status_code,
             res.text)

    if res.status_code != 200:
        _echoerr('cannot get topics')
        return {'topics': [], 'companies': []}

    try:
        data = res.json()['data']
        topics = [{'topic_name': node['translatedName'] or node['name'],
                   'num_problems': str(len(node['questionIds'] or [])),
                   'topic_slug': node['slug']}
                  for node in (edge['node'] for edge in data['questionTopicTags']['edges'])]
        companies = [{'company_name': c['name'],
                      'num_problems': str(c['questionCount']),
                      'company_slug': c['slug']}
                     for c in data['companyTags'] or []]
    except (AttributeError, KeyError, TypeError, ValueError):
        _echoerr('cannot parse topics')
        return {'topics': [], 'companies': []}

    return {
        'topics': topics,
        'companies': companies
        }


def get_problems_of_topic(topic_slug):
    request_body = {
        'operationName': 'getTopicTag',
        'variables': {'slug': topic_slug},
        'query': '''query getTopicTag($slug: String!) {
  topicTag(slug: $slug) {
    name
    translatedName
    questions {
      status
      questionId
      questionFrontendId
      title
      titleSlug
      translatedTitle
      stats
      difficulty
      isPaidOnly
    }
    frequencies
  }
}
'''}

    headers = _make_headers()

    log.info('get_problems_of_topic request: headers="%s" body="%s"', headers,
             request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)

    log.info('get_problems_of_topic response: status="%s" body="%s"',
             res.status_code, res.text)

    if res.status_code != 200:
        _echoerr('cannot get problems of the topic')
        return {'topic_name': topic_slug, 'problems': []}

    topic_tag = res.json()['data']['topicTag']

    if not topic_tag:
        return {'topic_name': topic_slug, 'problems': []}

    if topic_tag['frequencies']:
        id_to_frequency_map = json.loads(topic_tag['frequencies'])
    else:
        id_to_frequency_map = {}

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
            'favor': False,
            'frequency': id_to_frequency_map.get(p['questionId'], 0)}

    return {
        'topic_name': topic_tag['name'],
        'problems': [process_problem(p) for p in topic_tag['questions']]}


def get_problems_of_company(company_slug):
    request_body = {
        'operationName': 'getCompanyTag',
        'variables': {'slug': company_slug},
        'query': '''query getCompanyTag($slug: String!) {
  companyTag(slug: $slug) {
    name
    translatedName
    frequencies
    questions {
      ...questionFields
    }
  }
}

fragment questionFields on QuestionNode {
  status
  questionId
  questionFrontendId
  title
  titleSlug
  translatedTitle
  stats
  difficulty
  isPaidOnly
}
'''}

    headers = _make_headers()
    headers['Referer'] = 'https://leetcode.com/company/{}/'.format(company_slug)

    log.info('get_problems_of_company request: headers="%s" body="%s"', headers,
             request_body)
    res = session.post(LC_GRAPHQL, headers=headers, json=request_body)

    log.info('get_problems_of_company response: status="%s" body="%s"',
             res.status_code, res.text)

    if res.status_code != 200:
        _echoerr('cannot get problems of the company')
        return {'company_name': company_slug, 'problems': []}

    company_tag = res.json()['data']['companyTag']

    if not company_tag:
        _echoerr('cannot get problems of the company')
        return {'company_name': company_slug, 'problems': []}

    if company_tag['frequencies']:
        id_to_frequency_map = json.loads(company_tag['frequencies'])
    else:
        id_to_frequency_map = {}

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
            'favor': False,
            'frequencies': id_to_frequency_map.get(p['questionId'],
                                                   EMPTY_FREQUENCIES)[4:]}

    return {
        'company_name': company_tag['name'],
        'problems': [process_problem(p) for p in company_tag['questions']]}


def _start_task():
    global task_running, task_done, task_output, task_err
    # Reset the status here, not in the worker: Vim polls task_done right
    # after this returns, possibly before the worker thread has woken up.
    task_running = True
    task_done = False
    task_output = None
    task_err = ''
    task_trigger.release()


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
                task_output = test_solution(*task_input)
            elif task_name == 'submit_solution':
                task_output = submit_solution(*task_input)
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
