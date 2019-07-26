" vim: sts=4 sw=4 expandtab

let s:current_dir = expand("<sfile>:p:h")

python3 <<EOF
import os.path
import vim

plugin_dir = vim.eval('s:current_dir')
thirdparty_dir = os.path.join(plugin_dir, 'thirdparty')

if plugin_dir not in sys.path:
  sys.path.append(plugin_dir)

if thirdparty_dir not in sys.path:
  sys.path.append(thirdparty_dir)

import leetcode
EOF

let s:inited = py3eval('leetcode.inited')

if g:leetcode_debug
    python3 leetcode.enable_logging()
endif

if g:leetcode_china
    python3 leetcode.switch_china(1)
else
    python3 leetcode.switch_china(0)
endif

function! leetcode#SignIn(ask)
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

    let success = py3eval('leetcode.signin("'.username.'", "'.password.'")')

    if a:ask && success
        echo 'succesfully signed in as '.username
    endif
    return success
endfunction

function! s:CheckSignIn()
    if !py3eval('leetcode.is_login()')
        return leetcode#SignIn(0)
    endif
    return v:true
endfunction

function! s:SetupProblemWindow()
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal bufhidden=delete
    setlocal nospell
    setlocal nonumber
    setlocal norelativenumber
    setlocal nobuflisted
    setlocal filetype=markdown
    nnoremap <silent> <buffer> <return> :call <SID>GoToProblem()<cr>
    nnoremap <silent> <buffer> s :call <SID>GoToSubmissions()<cr>

    " add custom syntax rules
    syn match lcEasy /| Easy /hs=s+2
    syn match lcMedium /| Medium /hs=s+2
    syn match lcHard /| Hard /hs=s+2
    syn match lcDone /|X|/hs=s+1,he=e-1
    syn match lcTodo /|?|/hs=s+1,he=e-1
    syn match lcPaidOnly /\[P\]/

    " add custom highlighting rules
    hi! lcEasy ctermfg=lightgreen guifg=lightgreen
    hi! lcMedium ctermfg=yellow guifg=yellow
    hi! lcHard ctermfg=red guifg=red
    hi! lcDone ctermfg=green guifg=green
    hi! lcTodo ctermfg=yellow guifg=yellow
    hi! lcPaidOnly ctermfg=yellow guifg=yellow
endfunction

function! s:PrintProblemList(problems)
    " show the problems in a table
    let max_id_len = 1
    let max_title_len = 5
    for p in a:problems
        if strlen(p['title']) > max_title_len
            let max_title_len = strlen(p['title'].' [P]')
        endif
        if strlen(p['fid']) > max_id_len
            let max_id_len = strlen(p['fid'])
        endif
    endfor

    call append('$', ['', '## Problem List',
                \ '### Keys',
                \ '  - ret = open the problem',
                \ '  - s   = view the submissions',
                \ '### Indicators',
                \ '  - [P] = paid-only problems'])

    let head = '| | #'.repeat(' ', max_id_len-1).' | Title'.repeat(' ', max_title_len-5).' | Accepted | Difficulty |'
    let separator= '|-| '.repeat('-', max_id_len).' | '.repeat('-', max_title_len).' | -------- | ---------- |'
    call append('$', [separator, head, separator])

    let format = '|%s| %-'.string(max_id_len).'d | %-'.string(max_title_len).'S | %7.1f%% | %-10S |'
    let output = []
    for p in a:problems
        let title = substitute(p['title'], '`', "'", 'g')
        if p['paid_only']
            let title = title.' [P]'
        endif
        call add(output, printf(format, p['state'], p['fid'], title, p['ac_rate'] * 100, p['level']))
    endfor
    call add(output, separator)
    call append('$', output)
endfunction

function! s:ListProblemsOfTopic(topic)
    if s:CheckSignIn() == v:false
        return
    endif

    let problems = py3eval('leetcode.get_problems_of_topic('.string(a:topic).')')['problems']

    let s:leetcode_problem_slug_map = {}
    for p in problems
        let s:leetcode_problem_slug_map[p['fid']] = p['slug']
    endfor

    let s:leetcode_end_of_topics = 0
    let s:leetcode_end_of_companies = 0

    " create a window to show the problem list or go to the existing one
    let winnr = bufwinnr('LeetCode/List')
    if winnr == -1
        rightbelow new LeetCode/List
        call s:SetupProblemWindow()
    else
        execute winnr.'wincmd w'
    endif

    set modifiable

    " clear the buffer
    normal gg
    normal dG

    call append('$', ['LeetCode [' . a:topic . ']', repeat('=', 80), '',])

    call s:PrintProblemList(problems)

    normal gg
    normal dd

    setlocal nomodifiable

    " try maximizing the window
    try
        silent! only
    endtry
endfunction

function! s:ListProblemsOfCompany(company)
    if s:CheckSignIn() == v:false
        return
    endif

    let problems = py3eval('leetcode.get_problems_of_company('.string(a:company).')')['problems']

    let s:leetcode_problem_slug_map = {}
    for p in problems
        let s:leetcode_problem_slug_map[p['fid']] = p['slug']
    endfor

    let s:leetcode_end_of_topics = 0
    let s:leetcode_end_of_companies = 0

    " create a window to show the problem list or go to the existing one
    let winnr = bufwinnr('LeetCode/List')
    if winnr == -1
        rightbelow new LeetCode/List
        call s:SetupProblemWindow()
    else
        execute winnr.'wincmd w'
    endif

    set modifiable

    " clear the buffer
    normal gg
    normal dG

    call append('$', ['LeetCode [' . a:company . ']', repeat('=', 80), '',])

    call s:PrintProblemList(problems)

    normal gg
    normal dd

    setlocal nomodifiable

    " try maximizing the window
    try
        silent! only
    endtry
endfunction

function! leetcode#ListProblems()
    if s:CheckSignIn() == v:false
        return
    endif

    let problems = py3eval('leetcode.get_problems(' . string(g:leetcode_categories) . ')')

    let s:leetcode_problem_slug_map = {}
    for p in problems
        let s:leetcode_problem_slug_map[p['fid']] = p['slug']
    endfor

    let topics_and_companies = py3eval('leetcode.get_topics_and_companies()')
    let topics = topics_and_companies['topics']
    let companies = topics_and_companies['companies']

    let s:leetcode_topic_slug_map = {}
    for t in topics
        let s:leetcode_topic_slug_map[t['topic_slug']] = t['topic_name']
    endfor

    let s:leetcode_company_slug_map = {}
    for c in companies
        let s:leetcode_company_slug_map[c['company_slug']] = c['company_name']
    endfor

    " create a window to show the problem list or go to the existing one
    let winnr = bufwinnr('LeetCode/List')
    if winnr == -1
        rightbelow new LeetCode/List
        call s:SetupProblemWindow()
    else
        execute winnr.'wincmd w'
    endif

    set modifiable

    " clear the buffer
    normal gg
    normal dG

    " concatenate the topics into a string
    let topic_list = []
    for t in topics
        call add(topic_list, t['topic_slug'])
    endfor

    let topic_lines = s:FormatIntoColumns(topic_list)

    " concatenate the companies into a string
    let company_list = []
    for c in companies
        call add(company_list, c['company_slug'])
    endfor

    let company_lines = s:FormatIntoColumns(company_list)

    call append('$', ['LeetCode', repeat('=', 80), '',
                \ '## Topics', ''])

    call append('$', topic_lines)

    let s:leetcode_end_of_topics = line('$')

    call append('$', ['', '## Companies', ''])

    call append('$', company_lines)

    let s:leetcode_end_of_companies = line('$')

    call s:PrintProblemList(problems)

    normal gg
    normal dd

    setlocal nomodifiable

    " try maximizing the window
    try
        silent! only
    endtry
endfunction

function! s:GoToProblem()
    if s:CheckSignIn() == v:false
        return
    endif

    " Parse the problem number from the line
    let line = getline('.')
    let linenum = getcurpos()[1]

    if linenum <= s:leetcode_end_of_topics
        " The user is choosing a topic
        let topic = expand('<cWORD>')
        if has_key(s:leetcode_topic_slug_map, topic)
            call s:ListProblemsOfTopic(topic)
        endif
        return
    elseif linenum <= s:leetcode_end_of_companies
        " The user is choosing a company
        let company = expand('<cWORD>')
        if has_key(s:leetcode_company_slug_map, company)
            call s:ListProblemsOfCompany(company)
        endif
        return
    endif

    let fid = matchstr(line, '[1-9][0-9]*', 3)
    if has_key(s:leetcode_problem_slug_map, fid)
        let slug = s:leetcode_problem_slug_map[fid]
    else
        return
    endif

    " Download the problem
    let problem = py3eval('leetcode.get_problem("'.slug.'")')
    if type(problem) != v:t_dict
        return
    endif

    " create the solution file from the template
    execute 'rightbelow vnew '.problem['slug'].'.'.s:SolutionFileExt(g:leetcode_solution_filetype)
    call leetcode#ResetSolution(1)
endfunction

function! s:SolutionFileExt(ft_)
    let ft = a:ft_
    if ft == 'cpp'
        return 'cpp'
    elseif ft == 'java'
        return 'java'
    elseif ft == 'python'
        return 'py'
    elseif ft == 'python3'
        return 'py'
    elseif ft == 'c'
        return 'c'
    elseif ft == 'csharp'
        return 'cs'
    elseif ft == 'javascript'
        return 'js'
    elseif ft == 'ruby'
        return 'rb'
    elseif ft == 'swift'
        return 'swift'
    elseif ft == 'golang'
        return 'go'
    elseif ft == 'scala'
        return 'scala'
    elseif ft == 'kotlin'
        return 'kt'
    elseif ft == 'rust'
        return 'rs'
    endif
endfunction

function! leetcode#ResetSolution(latest_submission)
    if s:CheckSignIn() == v:false
        return
    endif

    " expand('%:t:r') returns the file name without extension
    let slug = expand('%:t:r')
    let problem = py3eval('leetcode.get_problem("'.slug.'")')
    let filetype = g:leetcode_solution_filetype
    if type(problem) != v:t_dict
        return
    endif

    if !has_key(problem['templates'], filetype)
        echo 'the file type is not supported'
        return
    endif

    " try downloading the latest submission
    let code = []
    if a:latest_submission
        let submissions = py3eval('leetcode.get_submissions("'.slug.'")')
        if type(submissions) == v:t_list
            for item in submissions
                let subm = py3eval('leetcode.get_submission('.item['id'].')')
                if type(subm) == v:t_dict && subm['filetype'] == filetype
                    let code = subm['code']
                    break
                endif
            endfor
        endif
    endif

    " clear the buffer
    normal gg
    normal dG

    " show the problem description as comments
    let output = []
    call add(output, s:CommentStart(filetype, problem['title']))
    let desc = '['.problem['level'].'] [AC:'.
                \ printf('%s %s of %s', problem['ac_rate'],
                \ problem['total_accepted'], problem['total_submission']).
                \ '] [filetype:'.filetype.']'
    call add(output, s:CommentLine(filetype, ''))
    call add(output, s:CommentLine(filetype, desc))
    call add(output, s:CommentLine(filetype, ''))
    for line in problem['desc']
        call add(output, s:CommentLine(filetype, line))
    endfor
    call add(output, s:CommentEnd(filetype))
    call append('$', output)

    " wrap the long lines according to the option textwidth
    normal gg
    normal gqG

    " append the submitted code or the code template
    if len(code) == 0
        let code = problem['templates'][filetype]
    endif
    call append('$', code)

    " go to the first line and delete it (a blank line)
    normal gg
    normal dd
endfunction

function! s:CommentStart(ft, title)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin', 'rust'], a:ft) >= 0
        let head = '/* '
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        let head = '# '
    elseif index(['golang'], a:ft) >= 0
        let head = '// '
    endif
    return head.a:title
endfunction

function! s:CommentLine(ft, line)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin', 'rust'], a:ft) >= 0
        return ' * '.a:line
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        return '# '.a:line
    elseif index(['golang'], a:ft) >= 0
        return '// '.a:line
    endif
    return a:line
endfunction

function! s:CommentEnd(ft)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin', 'rust'], a:ft) >= 0
        return ' * [End of Description] */'
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        return '# [End of Description]:'
    elseif index(['golang'], a:ft) >= 0
        return '// [End of Description]'
    else
        return ''
    endif
endfunction

function! s:GuessFileType()
    " We first try figuring out the file type from the comment in the first 10
    " lines. If we failed, we will try guessing it from the extension name.
    for line in getline(1, 10)
        let file_type = matchstr(line, '\[filetype:[[:alnum:]]\+\]')
        if file_type != ''
            return file_type[10:-2]
        endif
    endfor

    let ext = expand('%:e')
    if ext == 'cpp'
        return 'cpp'
    elseif ext == 'java'
        return 'java'
    elseif ext == 'py'
        " ask the user
        let pyver = input('Which Python [2/3]: ', '3')
        redraw
        if pyver == '2'
            return 'python'
        elseif pyver == '3'
            return 'python3'
        else
            echo 'unrecognized answer, default to Python3'
            return 'python3'
        endif
    elseif ext == 'c'
        return 'c'
    elseif ext == 'cs'
        return 'csharp'
    elseif ext == 'js'
        return 'javascript'
    elseif ext == 'rb'
        return 'ruby'
    elseif ext == 'swift'
        return 'swift'
    elseif ext == 'go'
        return 'golang'
    elseif ext == 'scala'
        return 'scala'
    elseif ext == 'kt'
        return 'kotlin'
    elseif ext == 'rs'
        return 'rust'
    else
        return ''
    endif
endfunction

function! leetcode#TestSolution()
    if s:CheckSignIn() == v:false
        return
    endif

    let fname = expand('%:t:r')
    if fname == ''
        echo 'no file name'
        return
    endif
    let slug = split(fname, '\.')[0]
    let file_type = s:GuessFileType()

    if has('timers')
        let ok = py3eval('leetcode.test_solution_async("'.slug.'", "'.file_type.'")')
        if ok
            call timer_start(200, function('s:CheckTask'), {'repeat': -1})
        endif
    else
        let result = py3eval('leetcode.test_solution("'.slug.'", "'.file_type.'")')
        if type(result) != v:t_dict
            return
        endif
        call s:ShowResult(result)
    endif
endfunction

function! leetcode#SubmitSolution()
    if s:CheckSignIn() == v:false
        return
    endif

    let fname = expand('%:t:r')
    if fname == ''
        echo 'no file name'
        return
    endif
    let slug = split(fname, '\.')[0]
    let file_type = s:GuessFileType()
    if has('timers')
        let ok = py3eval('leetcode.submit_solution_async("'.slug.'", "'.file_type.'")')
        if ok
            call timer_start(200, function('s:CheckTask'), {'repeat': -1})
        endif
    else
        let result = py3eval('leetcode.submit_solution("'.slug.'", "'.file_type.'")')
        if type(result) != v:t_dict
            return
        endif
        call s:ShowResult(result)
    endif
endfunction

function! s:MultiLineIfExists(title, block, level)
    let result = []
    if len(a:block) > 0
        call add(result, repeat('#', a:level).' '.a:title)
        for line in a:block
            call add(result, '    '.line)
        endfor
    endif
    return result
endfunction

function! s:TestCasePassText(pass_all)
    if a:pass_all
        return 'OK: all test cases passed'
    else
        return 'WARNING: some test cases failed'
    endif
endfunction

function! s:FormatResult(result_)
    let result = a:result_
    let output = [result['title'],
                \ repeat('=', min([winwidth(0), 80])),
                \ '## State',
                \ '  - '.result['state'],
                \ '## Runtime',
                \ '  - '.result['runtime']]
    if string(result['runtime_percentile'])
        call extend(output, [
                    \ '## Runtime Rank',
                    \ printf('  - Faster than %s%% submissions', result['runtime_percentile'])
                    \ ])
    endif

    if result['total'] > 0
        call extend(output, [
                    \ '## Test Cases',
                    \ '  - Passed: '.result['passed'],
                    \ '  - Total:  '.result['total'],
                    \ '  - '.s:TestCasePassText(result['passed'] == result['total'])
                    \ ])
    endif

    call extend(output, s:MultiLineIfExists('Error', result['error'], 2))
    call extend(output, s:MultiLineIfExists('Standard Output', result['stdout'], 2))

    call extend(output, s:MultiLineIfExists('Input', result['testcase'], 3))
    call extend(output, s:MultiLineIfExists('Actual Answer', result['answer'], 3))
    call extend(output, s:MultiLineIfExists('Expected Answer', result['expected_answer'], 3))
    return output
endfunction

function! s:ShowResult(result_)
    call s:CloseAnyPreview()

    let saved_winnr = winnr()
    rightbelow new LeetCode/Result
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

    let result = a:result_
    let output = s:FormatResult(result)
    call append('$', output)

    " go to the first line and delete it (it is a blank line)
    normal gg
    normal dd

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

    execute saved_winnr.'wincmd w'
endfunction

function! s:CheckTask(timer)
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
            call s:ShowResult(task_output)
        endif
    else
        echo 'unrecognized task name: '.task_name
    endif
endfunction

function! s:GoToSubmissions()
    if s:CheckSignIn() == v:false
        return
    endif

    " Parse the problem number from the line
    let line = getline('.')
    let fid = matchstr(line, '[1-9][0-9]*', 3)
    if has_key(s:leetcode_problem_slug_map, fid)
        let slug = s:leetcode_problem_slug_map[fid]
    else
        return
    endif

    call s:ShowSubmissions(slug)
endfunction

function! s:ViewSubmissions()
    if s:CheckSignIn() == v:false
        return
    endif
    " expand('%:t:r') returns the file name without the extension name
    let slug = expand('%:t:r')
    call s:ShowSubmissions(slug)
endfunction

function! s:ShowSubmissions(slug)
    let submissions = py3eval('leetcode.get_submissions("'.a:slug.'")')
    if type(submissions) != v:t_list
        return
    endif
    let problem = py3eval('leetcode.get_problem("'.a:slug.'")')
    if type(problem) != v:t_dict
        return
    endif

    let winnr = bufwinnr('LeetCode/Submissions')
    if winnr == -1
        rightbelow new LeetCode/Submissions
        setlocal buftype=nofile
        setlocal noswapfile
        setlocal bufhidden=delete
        setlocal nospell
        setlocal nonumber
        setlocal norelativenumber
        setlocal nobuflisted
        setlocal filetype=markdown
        nnoremap <silent> <buffer> <return> :call <SID>ViewSubmission()<cr>

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
        syn match lcNA /N\/A/

        " add custom highlighting rules
        hi! lcAccepted term=bold gui=bold ctermfg=lightgreen guifg=lightgreen
        hi! lcFailure term=bold gui=bold ctermfg=red guifg=red
        hi! lcNA ctermfg=gray guifg=gray
    else
        execute winnr.'wincmd w'
    endif

    set modifiable

    " clear the content
    normal gg
    normal dG

    " show the submissions in a table
    let max_time_len = 4
    let max_id_len = 2
    let max_runtime_len = 7
    for s in submissions
        if strlen(s['time']) > max_time_len
            let max_time_len = strlen(s['time'])
        endif
        if strlen(s['id']) > max_id_len
            let max_id_len = strlen(s['id'])
        endif
        if strlen(s['runtime']) > max_runtime_len
            let max_runtime_len = strlen(s['runtime'])
        endif
    endfor

    let output = []
    call add(output, '# '.problem['title'])
    call add(output, '')
    call add(output, '## Submissions')
    call add(output, '  - return = view submission')
    call add(output, '')
    let head = '| ID'.repeat(' ', max_id_len-2).' | Time'.repeat(' ', max_time_len-4).' | Status                | Runtime'.repeat(' ', max_runtime_len-7).
                \' |'
    let separator= '| '.repeat('-', max_id_len).' | '.repeat('-', max_time_len).' | --------------------- | '.repeat('-', max_runtime_len).' |'
    call extend(output, [separator, head, separator])

    let format = '| %-'.string(max_id_len).'S | %-'.string(max_time_len).'S | %-21S | %-'.string(max_runtime_len).'S |'
    for s in submissions
        call add(output, printf(format, s['id'], s['time'], s['status'], s['runtime']))
    endfor
    call add(output, separator)
    call append('$', output)

    normal gg
    normal dd

    setlocal nomodifiable
endfunction

function! s:ViewSubmission()
    if s:CheckSignIn() == v:false
        return
    endif

    " Parse the submission number from the line
    let line = getline('.')
    let id = matchstr(line, '[1-9][0-9]*')
    if !id
        return
    endif

    let subm = py3eval('leetcode.get_submission('.id.')')
    if type(subm) != v:t_dict
        return
    endif

    " create the submission file
    execute 'rightbelow vnew '.subm['slug'].'.'.id.'.'.s:SolutionFileExt(subm['filetype'])
    set modifiable

    " clear the buffer
    normal gg
    normal dG

    " show the submission description as comments
    let desc = s:FormatResult(subm)
    call extend(desc, ['', '## Runtime Rank',
                \ printf('  - Faster than %s submissions', subm['runtime_percentile'])])
    let filetype = subm['filetype']
    let output = [s:CommentStart(filetype, 'Submission '.id),
                \ s:CommentLine(filetype, '')]
    for line in desc
        call add(output, s:CommentLine(filetype, line))
    endfor
    call add(output, s:CommentEnd(filetype))
    call append('$', output)
    call append('$', subm['code'])

    " delete the first line (it is a blank line)
    normal gg
    normal dd
endfunction

function! s:CloseAnyPreview()
    try
        pclose
    catch /E444:/
        let curwin = winnr()
        for i in range(1, winnr('$'))
            execute i.'wincmd w'
            setlocal nopreviewwindow
        endfor
        execute curwin.'wincmd w'
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
