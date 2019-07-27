" vim: sts=4 sw=4 expandtab

let s:current_dir = expand("<sfile>:p:h")

python3 <<EOF
import os
import vim

plugin_dir = vim.eval('s:current_dir')
thirdparty_dir = os.path.join(plugin_dir, 'thirdparty')

if plugin_dir not in sys.path:
  sys.path.append(plugin_dir)

if thirdparty_dir not in sys.path:
  sys.path.append(thirdparty_dir)

if int(vim.eval('g:leetcode_china')):
    os.environ['LEETCODE_BASE_URL'] = 'https://leetcode-cn.com'
else:
    os.environ['LEETCODE_BASE_URL'] = 'https://leetcode.com'

import leetcode
EOF

let s:inited = py3eval('leetcode.inited')

if g:leetcode_debug
    python3 leetcode.enable_logging()
endif

function! leetcode#SignIn(ask) abort
    if !s:inited
        return v:false
    endif

    if a:ask || g:leetcode_username == '' || g:leetcode_password == ''
        let username = input('Username: ', g:leetcode_username)
        let password = inputsecret('Password: ')
        let g:leetcode_username = username
        let g:leetcode_password = password
        redraw
    else
        let username = g:leetcode_username
        let password = g:leetcode_password
    endif

    let expr = printf('leetcode.signin("%s", "%s")', username, password)
    let success = py3eval(expr)

    if a:ask && success
        echo 'succesfully signed in as '.username
    endif
    return success
endfunction

function! s:CheckSignIn() abort
    if !py3eval('leetcode.is_login()')
        return leetcode#SignIn(0)
    endif
    return v:true
endfunction

function! s:SetupProblemListBuffer() abort
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nobackup
    setlocal nonumber
    setlocal norelativenumber
    setlocal nospell
    setlocal filetype=markdown
    setlocal bufhidden=hide
    nnoremap <silent> <buffer> <return> :call <SID>HandleProblemListCR()<cr>
    nnoremap <silent> <buffer> s :call <SID>HandleProblemListS()<cr>

    syn match lcEasy /| Easy /hs=s+2
    syn match lcMedium /| Medium /hs=s+2
    syn match lcHard /| Hard /hs=s+2
    syn match lcDone /|X|/hs=s+1,he=e-1
    syn match lcTodo /|?|/hs=s+1,he=e-1
    syn match lcPaidOnly /\[P\]/

    hi! lcEasy ctermfg=lightgreen guifg=lightgreen
    hi! lcMedium ctermfg=yellow guifg=yellow
    hi! lcHard ctermfg=red guifg=red
    hi! lcDone ctermfg=green guifg=green
    hi! lcTodo ctermfg=yellow guifg=yellow
    hi! lcPaidOnly ctermfg=yellow guifg=yellow
endfunction

function! s:MaxWidthOfKey(list_of_dict, key, min_width) abort
    let max_width = a:min_width
    for item in a:list_of_dict
        let max_width = max([max_width, strwidth(item[a:key])])
    endfor
    return max_width
endfunction

function! s:PrintProblemList(problems) abort
    let b:leetcode_problems = a:problems

    let id_width = s:MaxWidthOfKey(a:problems, 'fid', 1)
    let title_width = s:MaxWidthOfKey(a:problems, 'title', 1) + 4

    call append('$', ['## Problem List',
                \ '',
                \ '### Keys',
                \ '  - <cr>  open the problem/go to the topic or company',
                \ '  - s     view the submissions',
                \ '### Indicators',
                \ '  - [P] = paid-only problems',
                \ ''])

    let format = '|%1S| %-' . id_width . 'S | %-' . title_width .
                \ 'S | %-8S | %-10S |'
    let header = printf(format, ' ', '#', 'Title', 'Accepted', 'Difficulty')
    let separator = printf(format, '-', repeat('-', id_width),
                \ repeat('-', title_width), repeat('-', 8), repeat('-', 10))

    call append('$', [header, separator])

    let problem_lines = []
    for problem in a:problems
        let title = substitute(problem['title'], '`', "'", 'g')
        if problem['paid_only']
            let title .= ' [P]'
        endif
        call add(problem_lines, printf(format, problem['state'],
                    \ problem['fid'], title,
                    \ printf('%7.1f%%', problem['ac_rate'] * 100),
                    \ problem['level']))
    endfor
    let b:leetcode_problem_start_line = line('$')
    call append('$', problem_lines)
    let b:leetcode_problem_end_line = line('$')
endfunction

function! s:ListProblemsOfTopic(topic_slug) abort
    let buf_name = 'leetcode:///problems/topic/' . a:topic_slug
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        return
    endif

    execute 'rightbelow new ' . buf_name
    call s:SetupProblemListBuffer()

    let expr = printf('leetcode.get_problems_of_topic("%s")', a:topic_slug)
    let problems = py3eval(expr)['problems']

    let b:leetcode_topic_start_line = 0
    let b:leetcode_topic_end_line = 0
    let b:leetcode_company_start_line = 0
    let b:leetcode_company_end_line = 0

    setlocal modifiable

    call append('$', ['# LeetCode [topic:' . a:topic_slug . ']', ''])

    call s:PrintProblemList(problems)

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only
endfunction

function! s:ListProblemsOfCompany(company_slug) abort
    let bufname = 'leetcode:///problems/company/' . a:company_slug
    if buflisted(bufname)
        execute bufnr(bufname) . 'buffer'
        return
    endif

    execute 'rightbelow new ' . bufname
    call s:SetupProblemListBuffer()

    let expr = printf('leetcode.get_problems_of_company("%s")', a:company_slug)
    let problems = py3eval(expr)['problems']

    let b:leetcode_topic_start_line = 0
    let b:leetcode_topic_end_line = 0
    let b:leetcode_company_start_line = 0
    let b:leetcode_company_end_line = 0

    setlocal modifiable

    call append('$', ['# LeetCode [company:' . a:company_slug . ']', ''])

    call s:PrintProblemList(problems)

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only
endfunction

function! leetcode#ListProblems() abort
    if s:CheckSignIn() == v:false
        return
    endif

    let buf_name = 'leetcode:///problems/all'
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        return
    endif

    let expr = printf('leetcode.get_problems(["all"])')
    let problems = py3eval(expr)

    let topics_and_companies = py3eval('leetcode.get_topics_and_companies()')
    let topics = topics_and_companies['topics']
    let companies = topics_and_companies['companies']

    execute 'rightbelow new ' . buf_name
    call s:SetupProblemListBuffer()

    set modifiable

    " concatenate the topics into a string
    let topic_slugs = map(topics, 'v:val["topic_slug"]')
    let topic_lines = s:FormatIntoColumns(topic_slugs)

    call append('$', ['# LeetCode', '', '## Topics', ''])

    let b:leetcode_topic_start_line = line('$')
    call append('$', topic_lines)
    let b:leetcode_topic_end_line = line('$')

    let company_slugs = map(companies, 'v:val["company_slug"]')
    let company_lines = s:FormatIntoColumns(company_slugs)

    call append('$', ['', '## Companies', ''])

    let b:leetcode_company_start_line = line('$')
    call append('$', company_lines)
    let b:leetcode_company_end_line = line('$')

    call append('$', '')
    call s:PrintProblemList(problems)

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only
endfunction

function! s:HandleProblemListCR() abort
    " Parse the problem number from the line
    let line_nr = line('.')

    if line_nr >= b:leetcode_topic_start_line &&
                \ line_nr < b:leetcode_topic_end_line
        let topic_slug = expand('<cWORD>')
        if topic_slug != ''
            call s:ListProblemsOfTopic(topic_slug)
        endif
        return
    endif

    if line_nr >= b:leetcode_company_start_line &&
                \ line_nr < b:leetcode_company_end_line
        let company_slug = expand('<cWORD>')
        if company_slug != ''
            call s:ListProblemsOfCompany(company_slug)
        endif
        return
    endif

    if line_nr >= b:leetcode_problem_start_line &&
                \ line_nr < b:leetcode_problem_end_line
        let problem_nr = line_nr - b:leetcode_problem_start_line
        let problem_slug = b:leetcode_problems[problem_nr]['slug']
        let problem_ext = s:SolutionFileExt(g:leetcode_solution_filetype)
        let problem_file_name = printf('%s.%s', problem_slug, problem_ext)

        if buflisted(problem_file_name)
            execute bufnr(problem_file_name) . 'buffer'
            return
        endif

        execute 'rightbelow vnew ' . problem_file_name
        call leetcode#ResetSolution(1)
    endif
endfunction

let s:file_type_to_ext = {
            \ 'cpp': 'cpp',
            \ 'java': 'java',
            \ 'python': 'py',
            \ 'python3': 'py',
            \ 'c': 'c',
            \ 'csharp': 'cs',
            \ 'javascript': 'js',
            \ 'ruby': 'rb',
            \ 'swift': 'swift',
            \ 'golang': 'go',
            \ 'scala': 'scala',
            \ 'kotlin': 'kt',
            \ 'rust': 'rs',
            \ }

function! s:SolutionFileExt(filetype) abort
    return s:file_type_to_ext[a:filetype]
endfunction

function! leetcode#ResetSolution(with_latest_submission) abort
    if s:CheckSignIn() == v:false
        return
    endif

    let problem_slug = expand('%:t:r')
    let expr = printf('leetcode.get_problem("%s")', problem_slug)
    let problem = py3eval(expr)
    if type(problem) != v:t_dict
        return
    endif

    let filetype = g:leetcode_solution_filetype
    if !has_key(problem['templates'], filetype)
        echo 'the file type is not supported: ' . filetype
        return
    endif

    let code = []
    if a:with_latest_submission
        let expr = printf('leetcode.get_submissions("%s")', problem_slug)
        let submissions = py3eval(expr)
        if type(submissions) == v:t_list
            for submission in submissions
                let expr = printf('leetcode.get_submission(%s)',
                            \ submission['id'])
                let detail = py3eval(expr)
                if type(detail) == v:t_dict && detail['filetype'] ==# filetype
                    let code = detail['code']
                    break
                endif
            endfor
        endif
    endif

    if len(code) == 0
        let code = problem['templates'][filetype]
    endif

    silent! normal! ggdG

    let output = []
    call add(output, s:CommentStart(filetype, problem['title']))
    let meta_format = '[%s] [AC:%s %s of %s] [filetype:%s]'
    let meta = printf(meta_format, problem['level'], problem['ac_rate'],
                \ problem['total_accepted'], problem['total_submission'],
                \ filetype)
    call add(output, s:CommentLine(filetype, ''))
    call add(output, s:CommentLine(filetype, meta))
    call add(output, s:CommentLine(filetype, ''))
    for line in problem['desc']
        call add(output, s:CommentLine(filetype, line))
    endfor
    call add(output, s:CommentEnd(filetype))
    call append('$', output)

    silent! normal! gggqG

    call append('$', code)

    silent! normal! ggdd
endfunction

function! s:CommentStart(filetype, title) abort
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala',
                \ 'kotlin', 'rust'], a:filetype) >= 0
        return '/* ' . a:title
    elseif index(['python', 'python3', 'ruby'], a:filetype) >= 0
        return '# ' . a:title
    elseif index(['golang'], a:filetype) >= 0
        return '// ' . a:title
    else
        return a:title
    endif
endfunction

function! s:CommentLine(filetype, line) abort
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala',
                \ 'kotlin', 'rust'], a:filetype) >= 0
        return ' * ' . a:line
    elseif index(['python', 'python3', 'ruby'], a:filetype) >= 0
        return '# '.a:line
    elseif index(['golang'], a:filetype) >= 0
        return '// '.a:line
    else
        return a:line
    endif
endfunction

function! s:CommentEnd(filetype) abort
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala',
                \ 'kotlin', 'rust'], a:filetype) >= 0
        return ' * [End of Description] */'
    elseif index(['python', 'python3', 'ruby'], a:filetype) >= 0
        return '# [End of Description]:'
    elseif index(['golang'], a:filetype) >= 0
        return '// [End of Description]'
    else
        return ''
    endif
endfunction

function! s:GuessFileType() abort
    " Try figuring out the file type from the comment in the first 10
    " lines. If failed, try guessing it from the extension name.
    for line in getline(1, 10)
        let filetype = matchstr(line, '\[filetype:[[:alnum:]]\+\]')
        if filetype != ''
            return filetype[10:-2]
        endif
    endfor

    let ext = expand('%:e')
    let guessed_filetype = ''
    let guess_count = 0
    for [item_filetype, item_ext] in items(s:file_type_to_ext)
        if item_ext ==? ext
            let guess_count += 1
            let guessed_filetype = item_filetype
        endif
    endfor

    if guess_count == 1
        return guessed_filetype
    endif

    if ext == 'py'
        let python_version = input('Which Python [2/3]: ', '3')
        redraw
        if python_version ==# '2'
            return 'python'
        elseif python_version ==# '3'
            return 'python3'
        else
            echo 'unrecognized answer, default to Python3'
            return 'python3'
        endif
    endif

    return ''
endfunction

function! leetcode#TestSolution() abort
    if s:CheckSignIn() == v:false
        return
    endif

    let file_name = expand('%:t:r')
    if file_name == ''
        echo 'no file name'
        return
    endif

    let slug = split(file_name, '\.')[0]
    let filetype = s:GuessFileType()

    if has('timers')
        let expr = printf('leetcode.test_solution_async("%s", "%s")',
                    \ slug, filetype)
        let ok = py3eval(expr)
        if ok
            call timer_start(200, function('s:CheckRunCodeTask'),
                        \ {'repeat': -1})
        endif
    else
        let expr = printf('leetcode.test_solution("%s", "%s")',
                    \ slug, filetype)
        let result = py3eval(expr)
        if type(result) != v:t_dict
            return
        endif
        call s:ShowRunResultInPreview(result)
    endif
endfunction

function! leetcode#SubmitSolution() abort
    if s:CheckSignIn() == v:false
        return
    endif

    let file_name = expand('%:t:r')
    if file_name == ''
        echo 'no file name'
        return
    endif

    let slug = split(file_name, '\.')[0]
    let filetype = s:GuessFileType()

    if has('timers')
        let expr = printf('leetcode.submit_solution_async("%s", "%s")',
                    \ slug, filetype)
        let ok = py3eval(expr)
        if ok
            call timer_start(200, function('s:CheckRunCodeTask'),
                        \ {'repeat': -1})
        endif
    else
        let expr = printf('leetcode.submit_solution("%s", "%s")',
                    \ slug, filetype)
        let result = py3eval(expr)
        if type(result) != v:t_dict
            return
        endif
        call s:ShowRunResultInPreview(result)
    endif
endfunction

function! s:FormatSection(title, block, level) abort
    let result = []
    if len(a:block) > 0
        call add(result, repeat('#', a:level) . ' ' . a:title)
        for line in a:block
            call add(result, '    ' . line)
        endfor
        call add(result, '')
    endif
    return result
endfunction

function! s:TestSummary(all_passed) abort
    if a:all_passed
        return 'OK: all test cases passed'
    else
        return 'WARNING: some test cases failed'
    endif
endfunction

function! s:FormatResult(result_) abort
    let result = a:result_
    let output = ['# ' . result['title'],
                \ '',
                \ '## State',
                \ '  - ' . result['state'],
                \ '',
                \ '## Runtime',
                \ '  - ' . result['runtime'],
                \ '']
    if string(result['runtime_percentile'])
        let message = printf('  - Faster than %s%% submissions',
                    \ result['runtime_percentile'])
        call extend(output, [
                    \ '## Runtime Rank',
                    \ message,
                    \ '',
                    \ ])
    endif

    if result['total'] > 0
        let test_summary = s:TestSummary(result['passed'] == result['total'])
        call extend(output, [
                    \ '## Test Cases',
                    \ '  - Passed: ' . result['passed'],
                    \ '  - Total:  ' . result['total'],
                    \ '  - ' . test_summary,
                    \ '',
                    \ ])
    endif

    call extend(output, s:FormatSection('Error', result['error'], 2))
    call extend(output, s:FormatSection('Standard Output', result['stdout'], 2))

    call extend(output, s:FormatSection('Input', result['testcase'], 3))
    call extend(output, s:FormatSection('Actual Answer', result['answer'], 3))
    call extend(output, s:FormatSection('Expected Answer',
                \ result['expected_answer'], 3))
    return output
endfunction

function! s:ShowRunResultInPreview(result) abort
    call s:CloseAnyPreview()

    let saved_winnr = winnr()
    rightbelow new leetcode:///result
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal bufhidden=delete
    setlocal nospell
    setlocal nonumber
    setlocal norelativenumber
    setlocal nocursorline
    setlocal nobuflisted
    setlocal filetype=markdown
    setlocal modifiable

    let output = s:FormatResult(a:result)
    call append('$', output)

    silent! normal! ggdd

    setlocal previewwindow
    setlocal nomodifiable
    setlocal nomodified

    " add custom syntax rules
    syn keyword lcAccepted Accepted
    syn match lcFailure /Wrong Answer/
    syn match lcFailure /Memory Limit Exceeded/
    syn match lcFailure /Output Limit Exceeded/
    syn match lcFailure /Time Limit Exceeded/
    syn match lcFailure /Runtime Error/
    syn match lcFailure /Internal Error/
    syn match lcFailure /Compile Error/
    syn match lcFailure /Unknown Error/
    syn match lcFailure /Unknown State/
    syn match lcOK /OK:/
    syn match lcWarning /WARNING:/

    " add custom highlighting rules
    hi! lcAccepted term=bold gui=bold ctermfg=lightgreen guifg=lightgreen
    hi! lcFailure term=bold gui=bold ctermfg=red guifg=red
    hi! link lcOK lcAccepted
    hi! link lcWarning lcFailure

    execute saved_winnr . 'wincmd w'
endfunction

function! s:CheckRunCodeTask(timer) abort
    if !py3eval('leetcode.task_done')
        let prog = py3eval('leetcode.task_progress')
        echo prog
        return
    endif

    echo 'Done'
    call timer_stop(a:timer)
    let task_name = py3eval('leetcode.task_name')
    let task_output = py3eval('leetcode.task_output')
    let task_err = py3eval('leetcode.task_err')

    if task_err != ''
        echom 'error: '.task_err
    endif

    if task_name == 'test_solution' || task_name == 'submit_solution'
        if type(task_output) == v:t_dict
            call s:ShowRunResultInPreview(task_output)
        endif
    else
        echo 'unrecognized task name: '.task_name
    endif
endfunction

function! s:HandleProblemListS() abort
    let line_nr = line('.')
    if line_nr >= b:leetcode_problem_start_line &&
                \ line_nr < b:leetcode_problem_end_line
        let problem_nr = line_nr - b:leetcode_problem_start_line
        let problem_slug = b:leetcode_problems[problem_nr]['slug']
        call s:ListSubmissions(problem_slug)
    endif
endfunction

function! s:ListSubmissions(slug) abort
    let buf_name = 'leetcode:///submissions/' . a:slug
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        return
    endif

    execute 'rightbelow new ' . buf_name

    let expr = printf('leetcode.get_submissions("%s")', a:slug)
    let submissions = py3eval(expr)
    let b:leetcode_submissions = submissions
    if type(submissions) != v:t_list
        return
    endif

    let expr = printf('leetcode.get_problem("%s")', a:slug)
    let problem = py3eval(expr)
    if type(problem) != v:t_dict
        return
    endif

    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nobackup
    setlocal bufhidden=hide
    setlocal nospell
    setlocal nonumber
    setlocal norelativenumber
    setlocal filetype=markdown
    nnoremap <silent> <buffer> <return> :call <SID>HandleSubmissionsCR()<cr>

    syn keyword lcAccepted Accepted
    syn match lcFailure /Wrong Answer/
    syn match lcFailure /Memory Limit Exceeded/
    syn match lcFailure /Output Limit Exceeded/
    syn match lcFailure /Time Limit Exceeded/
    syn match lcFailure /Runtime Error/
    syn match lcFailure /Internal Error/
    syn match lcFailure /Compile Error/
    syn match lcFailure /Unknown Error/
    syn match lcFailure /Unknown State/
    syn match lcNA /N\/A/

    hi! lcAccepted term=bold gui=bold ctermfg=lightgreen guifg=lightgreen
    hi! lcFailure term=bold gui=bold ctermfg=red guifg=red
    hi! lcNA ctermfg=gray guifg=gray

    set modifiable

    let time_width = s:MaxWidthOfKey(submissions, 'time', 4)
    let id_width = s:MaxWidthOfKey(submissions, 'id', 2)
    let runtime_width = s:MaxWidthOfKey(submissions, 'runtime', 7)

    let output = []
    call add(output, '# '.problem['title'])
    call add(output, '')
    call add(output, '## Submissions')
    call add(output, '  - return = view submission')
    call add(output, '')
    let format = '| %-' . id_width . 'S | %-' . time_width .
                \ 'S | %-21S | %-' . runtime_width . 'S |'
    let header = printf(format, 'ID', 'Time', 'Status', 'Runtime')
    let separator= printf(format, repeat('-', id_width),
                \ repeat('-', time_width), repeat('-', 21),
                \ repeat('-', runtime_width))
    call extend(output, [header, separator])
    call append('$', output)

    let submission_lines = []
    for submission in submissions
        let line = printf(format, submission['id'], submission['time'],
                    \ submission['status'], submission['runtime'])
        call add(submission_lines, line)
    endfor

    let b:leetcode_submission_start = line('$')
    call append('$', submission_lines)
    let b:leetcode_submission_end = line('$')

    silent! normal! ggdd
    setlocal nomodifiable
endfunction

function! s:HandleSubmissionsCR() abort
    let line_nr = line('.')
    if line_nr < b:leetcode_submission_start ||
                \ line_nr >= b:leetcode_submission_end
        return
    endif

    let submission_nr = line_nr - b:leetcode_submission_start
    let submission_id = b:leetcode_submissions[submission_nr]['id']

    let expr = printf('leetcode.get_submission(%s)', submission_id)
    let submission = py3eval(expr)
    if type(submission) != v:t_dict
        return
    endif

    let file_name = printf('%s.%s.%s', submission['slug'], submission_id,
                \ s:SolutionFileExt(submission['filetype']))

    if bufexists(file_name)
        execute bufnr(file_name) . 'buffer'
        return
    endif

    execute 'rightbelow vnew ' . file_name
    set modifiable

    " Show the submission description as comments.
    let result = s:FormatResult(submission)
    let filetype = submission['filetype']
    let output = [s:CommentStart(filetype, 'Submission ' . submission_id),
                \ s:CommentLine(filetype, '')]
    for line in result
        call add(output, s:CommentLine(filetype, line))
    endfor
    call add(output, s:CommentEnd(filetype))
    call append('$', output)
    call append('$', submission['code'])

    silent! normal! ggdd
endfunction

function! s:CloseAnyPreview() abort
    try
        pclose
    catch /E444:/
        let saved_winnr = winnr()
        for i in range(1, winnr('$'))
            execute i . 'wincmd w'
            setlocal nopreviewwindow
        endfor
        execute saved_winnr . 'wincmd w'
    endtry
endfunction


function! s:FormatIntoColumns(words) abort
    let max_word_width = 0
    for word in a:words
        if strwidth(word) > max_word_width
            let max_word_width = strwidth(word)
        endif
    endfor

    let num_columns = float2nr(floor(80 / (max_word_width + 1)))
    if num_columns == 0
        let num_columns = 1
    endif

    let num_rows = float2nr(ceil(len(a:words) / num_columns))
    let lines = []

    for i in range(num_rows)
        let line = ''
        for j in range(num_columns)
            let word_index = j * num_rows + i
            if word_index < len(a:words)
                let word = a:words[word_index]
            else
                let word = ''
            endif
            let line .= printf('%-' . max_word_width . 'S ', word)
        endfor
        call add(lines, line)
    endfor

    return lines
endfunction
