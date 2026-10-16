" vim: sts=4 sw=4 expandtab
"
" The LeetCode API in Vim script, used with g:leetcode_backend = 'vim'.
" Same functions and return values as autoload/leetcode.py, but needs only
" curl (see autoload/leetcode/http.vim), not Python.

let s:base_url = 'https://leetcode.com'
let s:cookies = {}
" Give up waiting for the judge after this many seconds.
let s:check_timeout = 120
" The running test/submit task, if any.
let s:task = {}

" Requests without a browser-like User-Agent have been reported to get 403s
" from LeetCode (PRs #77, #83).
let s:user_agent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
            \ . '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

function! leetcode#api#Init(base_url) abort
    let s:base_url = a:base_url
endfunction

" ---- helpers -----------------------------------------------------------------

function! s:Echoerr(msg) abort
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction

function! s:Describe(msg, res) abort
    return empty(a:res.error) ? a:msg : a:msg . ' (' . a:res.error . ')'
endfunction

function! s:Headers(referer) abort
    return {'Origin': s:base_url,
                \ 'Referer': empty(a:referer) ? s:base_url : a:referer,
                \ 'User-Agent': s:user_agent,
                \ 'X-Requested-With': 'XMLHttpRequest',
                \ 'X-CSRFToken': get(s:cookies, 'csrftoken', '')}
endfunction

function! s:Request(method, path, referer, json) abort
    let req = {'url': s:base_url . a:path, 'method': a:method,
                \ 'headers': s:Headers(a:referer), 'cookies': s:cookies}
    if a:json isnot v:null
        let req.json = a:json
    endif
    return req
endfunction

function! s:Get(path, ...) abort
    return leetcode#http#Request(s:Request('GET', a:path, get(a:, 1, ''), v:null))
endfunction

function! s:Post(path, json, referer) abort
    return leetcode#http#Request(s:Request('POST', a:path, a:referer, a:json))
endfunction

" res's JSON body if the status is 200 and it is a dict, else v:null.
function! s:JsonDict(res) abort
    if a:res.status != 200
        return v:null
    endif
    let data = leetcode#http#Json(a:res)
    return type(data) == v:t_dict ? data : v:null
endfunction

function! s:Str(value) abort
    return type(a:value) == v:t_string ? a:value : ''
endfunction

function! s:OrZero(value) abort
    return type(a:value) == v:t_number || type(a:value) == v:t_float ? a:value : 0
endfunction

function! s:ProblemUrl(slug) abort
    return s:base_url . '/problems/' . a:slug . '/description'
endfunction

function! s:LevelToName(level) abort
    return get({1: 'Easy', 2: 'Medium', 3: 'Hard'}, a:level, ' ')
endfunction

function! s:StateToFlag(state) abort
    return get({'ac': 'X', 'notac': '?'}, s:Str(a:state), ' ')
endfunction

let s:status_names = {10: 'Accepted', 11: 'Wrong Answer', 12: 'Memory Limit Exceeded',
            \ 13: 'Output Limit Exceeded', 14: 'Time Limit Exceeded', 15: 'Runtime Error',
            \ 16: 'Internal Error', 20: 'Compile Error', 21: 'Unknown Error'}

function! s:StatusToName(status) abort
    return get(s:status_names, a:status, 'Unknown State')
endfunction

function! s:BreakCodeLines(s) abort
    let s = substitute(s:Str(a:s), '\r\n', '\n', 'g')
    return split(substitute(s, nr2char(160), ' ', 'g'), "\n", 1)
endfunction

" Lines of a string (or of each string in a list); [] for blank text.
function! s:Split(s) abort
    if type(a:s) == v:t_list
        let lines = []
        for item in a:s
            call extend(lines, s:Split(item))
        endfor
        return lines
    endif
    let s = substitute(s:Str(a:s), '\r\n\=', '\n', 'g')
    return s =~# '^\_s*$' ? [] : split(s, "\n", 1)
endfunction

function! s:RemoveDescription(code) abort
    let eod = stridx(a:code, '[End of Description]')
    if eod == -1
        return a:code
    endif
    let eol = stridx(a:code, "\n", eod)
    return eol == -1 ? '' : a:code[eol + 1:]
endfunction

function! s:FormatPercentile(p) abort
    if type(a:p) == v:t_number || type(a:p) == v:t_float
        return printf('%.1f', 1.0 * a:p)
    endif
    return s:Str(a:p)
endfunction

function! s:ResponseError(res, default) abort
    if a:res.body =~# 'too fast'
        return 'you are sending the request too fast'
    endif
    let data = leetcode#http#Json(a:res)
    if type(data) == v:t_dict && !empty(get(data, 'error', ''))
        return string(data.error)[1:-2]
    endif
    return s:Describe(a:default, a:res)
endfunction

" ---- session -----------------------------------------------------------------

function! leetcode#api#IsLogin() abort
    return has_key(s:cookies, 'LEETCODE_SESSION')
endfunction

function! leetcode#api#StartSessionWithCookies(cookies) abort
    let s:cookies = filter(copy(a:cookies), '!empty(v:val)')
    if leetcode#api#GetProgress() is v:null
        let s:cookies = {}
        return v:false
    endif
    return v:true
endfunction

function! leetcode#api#SignOut() abort
    let s:cookies = {}
endfunction

function! leetcode#api#GetProgress() abort
    let res = s:Get('/api/progress/all/')
    if res.status != 200
        call s:Echoerr(s:Describe('cannot get the progress', res))
        return v:null
    endif
    let data = s:JsonDict(res)
    return data isnot v:null && has_key(data, 'solvedTotal') ? data : v:null
endfunction

" ---- problems ----------------------------------------------------------------

function! leetcode#api#GetProblems(categories) abort
    let problems = []
    for category in a:categories
        let content = s:JsonDict(s:Get('/api/problems/' . category . '/'))
        if content is v:null
            call s:Echoerr('cannot get the category: ' . category)
            continue
        endif
        for p in content.stat_status_pairs
            if p.stat.question__hide
                continue
            endif
            call add(problems, {
                        \ 'state': s:StateToFlag(p.status),
                        \ 'id': p.stat.question_id,
                        \ 'fid': p.stat.frontend_question_id,
                        \ 'title': p.stat.question__title,
                        \ 'slug': p.stat.question__title_slug,
                        \ 'paid_only': p.paid_only,
                        \ 'ac_rate': 1.0 * p.stat.total_acs / max([p.stat.total_submitted, 1]),
                        \ 'level': s:LevelToName(p.difficulty.level),
                        \ 'favor': p.is_favor,
                        \ 'category': content.category_slug,
                        \ 'frequency': s:OrZero(p.frequency)})
        endfor
    endfor
    return sort(problems, {a, b -> a.id - b.id})
endfunction

let s:question_query = 'query getQuestionDetail($titleSlug : String!) {
            \ question(titleSlug: $titleSlug) { questionId questionFrontendId title content
            \ stats difficulty codeDefinition sampleTestCase enableRunCode translatedContent } }'

function! leetcode#api#GetProblem(slug) abort
    let res = s:Post('/graphql', {'query': s:question_query,
                \ 'variables': {'titleSlug': a:slug},
                \ 'operationName': 'getQuestionDetail'}, s:ProblemUrl(a:slug))
    let data = s:JsonDict(res)
    let q = data is v:null ? v:null : get(get(data, 'data', {}), 'question', v:null)
    if type(q) != v:t_dict
        call s:Echoerr('cannot get the problem: ' . a:slug)
        return v:null
    endif
    let content = !empty(s:Str(q.translatedContent)) ? q.translatedContent : s:Str(q.content)
    if empty(content)
        call s:Echoerr('cannot get the problem: ' . a:slug)
        return v:null
    endif

    let problem = {
                \ 'id': q.questionId,
                \ 'fid': q.questionFrontendId,
                \ 'title': q.title,
                \ 'slug': a:slug,
                \ 'level': q.difficulty,
                \ 'desc': leetcode#html#ToLines(content),
                \ 'templates': {},
                \ 'testable': q.enableRunCode,
                \ 'testcase': s:Split(q.sampleTestCase),
                \ }
    for t in json_decode(q.codeDefinition)
        let problem.templates[t.value] = s:BreakCodeLines(t.defaultCode)
    endfor
    let stats = json_decode(q.stats)
    let problem.total_accepted = stats.totalAccepted
    let problem.total_submission = stats.totalSubmission
    let problem.ac_rate = stats.acRate
    return problem
endfunction

let s:topic_query = 'query getTopicTag($slug: String!) { topicTag(slug: $slug) {
            \ name translatedName questions { status questionId questionFrontendId title
            \ titleSlug translatedTitle stats difficulty isPaidOnly } frequencies } }'

let s:company_query = 'query getCompanyTag($slug: String!) { companyTag(slug: $slug) {
            \ name translatedName frequencies questions { ...questionFields } } }
            \ fragment questionFields on QuestionNode { status questionId questionFrontendId
            \ title titleSlug translatedTitle stats difficulty isPaidOnly }'

function! s:TagProblem(p, frequency_key, frequency) abort
    let stats = json_decode(a:p.stats)
    let problem = {
                \ 'state': s:StateToFlag(a:p.status),
                \ 'id': a:p.questionId,
                \ 'fid': a:p.questionFrontendId,
                \ 'title': a:p.title,
                \ 'slug': a:p.titleSlug,
                \ 'paid_only': a:p.isPaidOnly,
                \ 'ac_rate': 1.0 * stats.totalAcceptedRaw / max([stats.totalSubmissionRaw, 1]),
                \ 'level': a:p.difficulty,
                \ 'favor': v:false,
                \ }
    let problem[a:frequency_key] = a:frequency
    return problem
endfunction

function! s:Tag(query, operation, field, slug, referer) abort
    let res = s:Post('/graphql', {'operationName': a:operation, 'variables': {'slug': a:slug},
                \ 'query': a:query}, a:referer)
    let data = s:JsonDict(res)
    let tag = data is v:null ? v:null : get(get(data, 'data', {}), a:field, v:null)
    return type(tag) == v:t_dict ? tag : v:null
endfunction

function! s:Frequencies(tag) abort
    let raw = get(a:tag, 'frequencies', v:null)
    return empty(s:Str(raw)) ? {} : json_decode(raw)
endfunction

function! leetcode#api#GetProblemsOfTopic(slug) abort
    let tag = s:Tag(s:topic_query, 'getTopicTag', 'topicTag', a:slug, '')
    if tag is v:null
        call s:Echoerr('cannot get problems of the topic')
        return {'topic_name': a:slug, 'problems': []}
    endif
    let freq = s:Frequencies(tag)
    return {'topic_name': tag.name,
                \ 'problems': map(copy(tag.questions),
                \   's:TagProblem(v:val, "frequency", get(freq, v:val.questionId, 0))')}
endfunction

function! leetcode#api#GetProblemsOfCompany(slug) abort
    let tag = s:Tag(s:company_query, 'getCompanyTag', 'companyTag', a:slug,
                \ s:base_url . '/company/' . a:slug . '/')
    if tag is v:null
        call s:Echoerr('cannot get problems of the company')
        return {'company_name': a:slug, 'problems': []}
    endif
    let freq = s:Frequencies(tag)
    let empty_freq = [0, 0, 0, 0, 0, 0, 0, 0]
    return {'company_name': tag.name,
                \ 'problems': map(copy(tag.questions),
                \   's:TagProblem(v:val, "frequencies", get(freq, v:val.questionId, empty_freq)[4:])')}
endfunction

let s:topics_and_companies_query = 'query getTopicsAndCompanies {
            \ questionTopicTags { edges { node { name translatedName slug questionIds } } }
            \ companyTags { name slug questionCount } }'

function! leetcode#api#GetTopicsAndCompanies() abort
    let res = s:Post('/graphql', {'operationName': 'getTopicsAndCompanies', 'variables': {},
                \ 'query': s:topics_and_companies_query}, s:base_url . '/problemset/')
    if res.status != 200
        call s:Echoerr('cannot get topics')
        return {'topics': [], 'companies': []}
    endif
    let data = s:JsonDict(res)
    let data = data is v:null ? {} : get(data, 'data', {})
    let tags = type(data) == v:t_dict ? get(data, 'questionTopicTags', v:null) : v:null
    let edges = type(tags) == v:t_dict ? get(tags, 'edges', v:null) : v:null
    let companies = type(data) == v:t_dict ? get(data, 'companyTags', v:null) : v:null
    if type(edges) != v:t_list
        call s:Echoerr('cannot parse topics')
        return {'topics': [], 'companies': []}
    endif
    let topics = []
    for t in map(copy(edges), 'v:val.node')
        call add(topics, {'topic_name': !empty(s:Str(t.translatedName)) ? t.translatedName : t.name,
                    \ 'num_problems': string(len(t.questionIds)), 'topic_slug': t.slug})
    endfor
    let companies = type(companies) == v:t_list ? companies : []
    call map(companies, '{"company_name": v:val.name, "company_slug": v:val.slug,'
                \ . ' "num_problems": string(v:val.questionCount)}')
    return {'topics': topics, 'companies': companies}
endfunction

" ---- submissions -------------------------------------------------------------

function! leetcode#api#GetSubmissions(slug) abort
    let data = s:JsonDict(s:Get('/api/submissions/' . a:slug . '/', s:ProblemUrl(a:slug)))
    if data is v:null
        call s:Echoerr('cannot find the submissions of problem: ' . a:slug)
        return v:null
    endif
    let submissions = []
    for r in data.submissions_dump
        call add(submissions, {
                    \ 'id': split(r.url, '/', 1)[3],
                    \ 'time': substitute(r.time, nr2char(160), ' ', 'g'),
                    \ 'status': r.status_display,
                    \ 'runtime': r.runtime})
    endfor
    return submissions
endfunction

let s:submission_query = 'query submissionDetails($submissionId: Int!) {
            \ submissionDetails(submissionId: $submissionId) { runtimeDisplay runtimePercentile
            \ memoryDisplay memoryPercentile code statusCode totalCorrect totalTestcases lastTestcase codeOutput expectedOutput
            \ runtimeError compileError lang { name } question { questionId titleSlug } } }'

function! leetcode#api#GetSubmission(sid) abort
    let res = s:Post('/graphql', {'operationName': 'submissionDetails',
                \ 'variables': {'submissionId': str2nr(a:sid)}, 'query': s:submission_query},
                \ s:base_url . '/submissions/detail/' . a:sid . '/')
    let data = s:JsonDict(res)
    let d = data is v:null ? v:null : get(get(data, 'data', {}), 'submissionDetails', v:null)
    if type(d) != v:t_dict
        call s:Echoerr('cannot find the submission: ' . a:sid)
        return v:null
    endif
    let error = !empty(s:Str(d.compileError)) ? d.compileError : s:Str(d.runtimeError)
    let submission = {
                \ 'id': a:sid,
                \ 'state': s:StatusToName(s:OrZero(d.statusCode)),
                \ 'runtime': !empty(s:Str(d.runtimeDisplay)) ? d.runtimeDisplay : 'N/A',
                \ 'passed': string(d.totalCorrect),
                \ 'total': string(d.totalTestcases),
                \ 'testcase': s:Split(s:Str(d.lastTestcase)),
                \ 'answer': s:Split(s:Str(d.codeOutput)),
                \ 'expected_answer': s:Split(s:Str(d.expectedOutput)),
                \ 'problem_id': d.question.questionId,
                \ 'slug': d.question.titleSlug,
                \ 'filetype': d.lang.name,
                \ 'error': empty(error) ? [] : s:Split(error),
                \ 'stdout': [],
                \ 'runtime_percentile': s:FormatPercentile(d.runtimePercentile),
                \ 'memory': s:Str(get(d, 'memoryDisplay', '')),
                \ 'memory_percentile': s:FormatPercentile(get(d, 'memoryPercentile', v:null)),
                \ }
    let submission.code = split(s:Str(d.code), '\r\=\n', 1)
    if !empty(submission.code) && submission.code[-1] ==# ''
        call remove(submission.code, -1)
    endif

    let problem = leetcode#api#GetProblem(submission.slug)
    if problem is v:null
        return v:null
    endif
    let submission.title = problem.title
    return submission
endfunction

" ---- running and submitting code -------------------------------------------
"
" Both run in the background: the requests go through curl jobs, and the
" judge is polled with a timer. When done, callback(output, error) is called
" with the result dict (or v:null) and an error message (or '').

function! s:TaskRunning() abort
    return !empty(s:task)
endfunction

function! s:StartTask(name, callback) abort
    if s:TaskRunning()
        call s:Echoerr('there is other task running: ' . s:task.name)
        return {}
    endif
    let s:task = {'name': a:name, 'callback': a:callback,
                \ 'deadline': reltimefloat(reltime()) + s:check_timeout}
    return s:task
endfunction

function! s:EndTask(task, output, error) abort
    let s:task = {}
    call a:task.callback(a:output, a:error)
endfunction

function! leetcode#api#TaskName() abort
    return get(s:task, 'name', '')
endfunction

function! leetcode#api#TestSolutionAsync(problem_id, title, slug, filetype, code, test_input,
            \ callback) abort
    let task = s:StartTask('test_solution', a:callback)
    if empty(task)
        return v:false
    endif
    let body = {'data_input': a:test_input, 'lang': a:filetype,
                \ 'question_id': '' . a:problem_id, 'test_mode': v:false,
                \ 'typed_code': s:RemoveDescription(a:code)}
    let Finish = {result -> extend(result, {'testcase': split(a:test_input, "\n", 1),
                \ 'title': a:title})}
    call leetcode#http#RequestAsync(
                \ s:Request('POST', '/problems/' . a:slug . '/interpret_solution/',
                \           s:ProblemUrl(a:slug), body),
                \ function('s:OnStarted', [task, 'interpret_id', v:false, Finish,
                \          'cannot test the solution for ' . a:slug]))
    return v:true
endfunction

function! leetcode#api#SubmitSolutionAsync(slug, filetype, code, callback) abort
    let task = s:StartTask('submit_solution', a:callback)
    if empty(task)
        return v:false
    endif
    let problem = leetcode#api#GetProblem(a:slug)
    if problem is v:null
        call s:EndTask(task, v:null, 'cannot get the problem: ' . a:slug)
        return v:true
    endif
    let body = {'data_input': problem.testcase, 'lang': a:filetype,
                \ 'question_id': '' . problem.id, 'test_mode': v:false,
                \ 'typed_code': s:RemoveDescription(a:code), 'judge_type': 'large'}
    let Finish = {result -> extend(result, {'title': problem.title})}
    call leetcode#http#RequestAsync(
                \ s:Request('POST', '/problems/' . a:slug . '/submit/', s:ProblemUrl(a:slug), body),
                \ function('s:OnStarted', [task, 'submission_id', v:true, Finish,
                \          'cannot submit the solution for ' . a:slug]))
    return v:true
endfunction

function! s:OnStarted(task, id_key, is_submit, finish, error, res) abort
    let data = s:JsonDict(a:res)
    let id = data is v:null ? '' : get(data, a:id_key, '')
    if empty(id)
        call s:EndTask(a:task, v:null, s:ResponseError(a:res, a:error))
        return
    endif
    call s:Poll(a:task, id, a:is_submit, a:finish)
endfunction

function! s:Poll(task, id, is_submit, finish, ...) abort
    call leetcode#http#RequestAsync(
                \ s:Request('GET', '/submissions/detail/' . a:id . '/check/', '', v:null),
                \ function('s:OnCheck', [a:task, a:id, a:is_submit, a:finish]))
endfunction

function! s:OnCheck(task, id, is_submit, finish, res) abort
    let r = s:JsonDict(a:res)
    if r is v:null
        call s:EndTask(a:task, v:null, s:Describe('cannot get the execution result', a:res))
        return
    endif
    let state = s:Str(get(r, 'state', ''))
    if state ==# 'SUCCESS'
        call s:EndTask(a:task, a:finish(s:ParseResult(r, a:is_submit)), '')
    elseif state ==# 'PENDING' || state ==# 'STARTED'
        echo state ==# 'PENDING' ? 'Pending...' : 'Running...'
        if reltimefloat(reltime()) > a:task.deadline
            call s:EndTask(a:task, v:null, printf('gave up waiting for the judge after %ds',
                        \ s:check_timeout))
            return
        endif
        call timer_start(1000, function('s:Poll', [a:task, a:id, a:is_submit, a:finish]))
    else
        call s:EndTask(a:task, v:null, 'unexpected judge state: ' . state)
    endif
endfunction

function! s:ParseResult(r, is_submit) abort
    let errors = []
    for key in sort(keys(a:r))
        if key =~# 'error' && !empty(a:r[key])
            call add(errors, a:r[key])
        endif
    endfor
    let result = {
                \ 'answer': get(a:r, 'code_answer', []),
                \ 'runtime': get(a:r, 'status_runtime', ''),
                \ 'state': s:StatusToName(get(a:r, 'status_code', 0)),
                \ 'testcase': s:Split(get(a:r, 'input', get(a:r, 'last_testcase', ''))),
                \ 'passed': s:OrZero(get(a:r, 'total_correct', 0)),
                \ 'total': s:OrZero(get(a:r, 'total_testcases', 0)),
                \ 'error': s:Split(errors),
                \ 'runtime_percentile': s:FormatPercentile(get(a:r, 'runtime_percentile', '')),
                \ 'memory': s:Str(get(a:r, 'status_memory', '')),
                \ 'memory_percentile': s:FormatPercentile(get(a:r, 'memory_percentile', '')),
                \ }
    if a:is_submit
        let result.answer = s:Split(get(a:r, 'code_output', ''))
        let result.expected_answer = s:Split(get(a:r, 'expected_output', ''))
        let result.stdout = s:Split(get(a:r, 'std_output', ''))
    else
        " Test runs can't tell accepted answers from wrong ones.
        if result.state ==# 'Accepted'
            let result.state = 'Finished'
        endif
        let result.stdout = s:Split(get(a:r, 'code_output', []))
        let result.expected_answer = get(a:r, 'expected_code_answer', [])
        " The judge's verdict on the answers, when it gives one.
        let result.correct_answer = get(a:r, 'correct_answer', v:null)
    endif
    return result
endfunction
