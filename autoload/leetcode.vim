let s:current_dir = expand("<sfile>:p:h")

python3 import vim
python3 if not vim.eval('s:current_dir') in sys.path: sys.path.append(vim.eval('s:current_dir'))
python3 import leetcode

let s:inited = py3eval('leetcode.inited')

if g:leetcode_debug
    python3 leetcode.enable_logging()
endif

function! leetcode#SignIn(ask)
    if !s:inited
        echoerr 'please install python packages beautifulsoup4 and requests'
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

function! leetcode#CheckSignIn()
    if !py3eval('leetcode.is_login()')
        return leetcode#SignIn(0)
    endif
    return v:true
endfunction

function! leetcode#ListProblems()
    if leetcode#CheckSignIn() == v:false
        return
    endif

    let problems = py3eval('leetcode.get_problems('.string(g:leetcode_categories).')')
    let s:leetcode_problem_slug_map = {}
    for p in problems
        let s:leetcode_problem_slug_map[p['fid']] = p['slug']
    endfor

    " create a window to show the problem list or go to the existing one
    let winnr = bufwinnr('LeetCode/List')
    if winnr == -1
        rightbelow new LeetCode/List
        setlocal buftype=nofile
        setlocal noswapfile
        setlocal bufhidden=delete
        setlocal nospell
        setlocal nonumber
        setlocal norelativenumber
        setlocal nocursorline
        setlocal nobuflisted
        setlocal filetype=markdown
        nnoremap <silent> <buffer> <return> :call leetcode#GoToProblem()<cr>
        nnoremap <silent> <buffer> s :call leetcode#GoToSubmissions()<cr>

        " add custom syntax rules
        syn match lcEasy /| Easy /hs=s+2
        syn match lcMedium /| Medium /hs=s+2
        syn match lcHard /| Hard /hs=s+2
        syn match lcDone /|X|/hs=s+1,he=e-1
        syn match lcTodo /|?|:/hs=s+1,he=e-1

        " add custom highlighting rules
        hi! lcEasy ctermfg=lightgreen guifg=lightgreen
        hi! lcMedium ctermfg=yellow guifg=yellow
        hi! lcHard ctermfg=red guifg=red
        hi! lcDone ctermfg=green guifg=green
        hi! lcTodo ctermfg=yellow guifg=yellow
    else
        execute winnr.'wincmd w'
    endif

    set modifiable

    " show the problems in a table
    let max_id_len = 1
    let max_title_len = 5
    for p in problems
        if strlen(p['title']) > max_title_len
            let max_title_len = strlen(p['title'])
        endif
        if strlen(p['fid']) > max_id_len
            let max_id_len = strlen(p['fid'])
        endif
    endfor

    call append('$', ['LeetCode', repeat('=', 80), '', '## Problem List', '  - return = open the problem',
                \ '  - s      = view the submissions', ''])

    let head = '| | #'.repeat(' ', max_id_len-1).' | Title'.repeat(' ', max_title_len-5).' | Accepted | Difficulty |'
    let separator= '|-| '.repeat('-', max_id_len).' | '.repeat('-', max_title_len).' | -------- | ---------- |'
    call append('$', [separator, head, separator])

    let format = '|%s| %-'.string(max_id_len).'d | %-'.string(max_title_len).'S | %7.1f%% | %-10S |'
    let output = []
    for p in problems
        call add(output, printf(format, p['state'], p['fid'], p['title'], p['ac_rate'] * 100, p['level']))
    endfor
    call add(output, separator)
    call append('$', output)

    normal gg
    normal dd

    setlocal nomodifiable

    " try maximizing the window
    try
        only
    endtry
endfunction

function! leetcode#GoToProblem()
    if leetcode#CheckSignIn() == v:false
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

    " Download the problem
    let problem = py3eval('leetcode.get_problem("'.slug.'")')
    if type(problem) != v:t_dict
        return
    endif

    " create the solution file from the template
    execute 'rightbelow new '.problem['slug'].'.'.leetcode#SolutionFileExt(g:leetcode_solution_filetype)
    call leetcode#ResetSolution()

    " close the problem list
    let winnr = bufwinnr('LeetCode/List')
    if winnr != -1
        execute winnr.'hide'
    endif

    set nomodified
endfunction

function! leetcode#SolutionFileExt(ft_)
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
    endif
endfunction

function! leetcode#ResetSolution()
    if leetcode#CheckSignIn() == v:false
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

    " clear the buffer
    normal gg
    normal dG

    " show the problem description as comments
    let output = []
    call add(output, leetcode#CommentStart(filetype, problem['title']))
    let desc = '['.problem['level'].'] [AC:'.
                \ printf('%s %s of %s', problem['ac_rate'],
                \ problem['total_accepted'], problem['total_submission']).
                \ '] [filetype:'.filetype.']'
    call add(output, leetcode#CommentLine(filetype, ''))
    call add(output, leetcode#CommentLine(filetype, desc))
    call add(output, leetcode#CommentLine(filetype, ''))
    for line in problem['desc']
        call add(output, leetcode#CommentLine(filetype, line))
    endfor
    call add(output, leetcode#CommentEnd(filetype))
    call append('0', output)

    " wrap the long lines according to the option textwidth
    normal gg
    normal gqG

    " append the code template
    call append('$', problem['templates'][filetype])
endfunction

function! leetcode#CommentStart(ft, title)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin'], a:ft) >= 0
        let head = '/* '
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        let head = '# '
    elseif index(['golang'], a:ft) >= 0
        let head = '// '
    endif
    return head.a:title
endfunction

function! leetcode#CommentLine(ft, line)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin'], a:ft) >= 0
        return ' * '.a:line
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        return '# '.a:line
    elseif index(['golang'], a:ft) >= 0
        return '// '.a:line
    endif
    return a:line
endfunction

function! leetcode#CommentEnd(ft)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin'], a:ft) >= 0
        return ' * [End of Description] */'
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        return '# [End of Description]:'
    elseif index(['golang'], a:ft) >= 0
        return '// [End of Description]'
    else
        return ''
    endif
endfunction

function! leetcode#GuessFileType()
    " We first try figuring out the file type from the comment in the first 10
    " lines. If we failed, we will try guessing it from the extension name.
    for line in getline(1, 10)
        let file_type = matchstr(line, '\[filetype:[[:alpha:]]\+\]')
        if file_type
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
    else
        return ''
    endif
endfunction

function! leetcode#TestSolution()
    if leetcode#CheckSignIn() == v:false
        return
    endif

    let fname = expand('%:t:r')
    if fname == ''
        echo 'no file name'
        return
    endif
    let slug = split(fname, '\.')[0]
    let file_type = leetcode#GuessFileType()

    if has('timers')
        let ok = py3eval('leetcode.test_solution_async("'.slug.'", "'.file_type.'")')
        if ok
            call timer_start(200, 'leetcode#CheckTask', {'repeat': -1})
        endif
    else
        let result = py3eval('leetcode.test_solution("'.slug.'", "'.file_type.'")')
        if type(result) != v:t_dict
            return
        endif
        call leetcode#ShowResult(result)
    endif
endfunction

function! leetcode#SubmitSolution()
    if leetcode#CheckSignIn() == v:false
        return
    endif

    let fname = expand('%:t:r')
    if fname == ''
        echo 'no file name'
        return
    endif
    let slug = split(fname, '\.')[0]
    let file_type = leetcode#GuessFileType()
    if has('timers')
        let ok = py3eval('leetcode.submit_solution_async("'.slug.'", "'.file_type.'")')
        if ok
            call timer_start(200, 'leetcode#CheckTask', {'repeat': -1})
        endif
    else
        let result = py3eval('leetcode.submit_solution("'.slug.'", "'.file_type.'")')
        if type(result) != v:t_dict
            return
        endif
        call leetcode#ShowResult(result)
    endif
endfunction

function! leetcode#MultiLineIfExists(title, block, level)
    let result = []
    if len(a:block) > 0
        call add(result, repeat('#', a:level).' '.a:title)
        for line in a:block
            call add(result, '    '.line)
        endfor
    endif
    return result
endfunction

function! leetcode#TestCasePassText(pass_all)
    if a:pass_all
        return 'OK: all test cases passed'
    else
        return 'WARNING: some test cases failed'
    endif
endfunction

function! leetcode#FormatResult(result_)
    let result = a:result_
    let output = [result['title'],
                \ repeat('=', min([winwidth(0), 80])),
                \ '## State',
                \ '  - '.result['state'],
                \ '## Runtime',
                \ '  - '.result['runtime'],
                \ ]

    if result['total'] > 0
        call extend(output, [
                    \ '## Test Cases',
                    \ '  - Passed: '.result['passed'],
                    \ '  - Total:  '.result['total'],
                    \ '  - '.leetcode#TestCasePassText(result['passed'] == result['total'])
                    \ ])
    endif

    call extend(output, leetcode#MultiLineIfExists('Error', result['error'], 2))
    call extend(output, leetcode#MultiLineIfExists('Standard Output', result['stdout'], 2))

    if len(result['testcase']) || len(result['answer']) || len(result['expected_answer'])
        call add(output, '## Failed Test Case')
    endif
    call extend(output, leetcode#MultiLineIfExists('Input', result['testcase'], 3))
    call extend(output, leetcode#MultiLineIfExists('Actual Answer', result['answer'], 3))
    call extend(output, leetcode#MultiLineIfExists('Expected Answer', result['expected_answer'], 3))
    return output
endfunction

function! leetcode#ShowResult(result_)
    call leetcode#CloseAnyPreview()

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
    let output = leetcode#FormatResult(result)
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

function! leetcode#CheckTask(timer)
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
            call leetcode#ShowResult(task_output)
        endif
    else
        echo 'unrecognized task name: '.task_name
    endif
endfunction

function! leetcode#GoToSubmissions()
    if leetcode#CheckSignIn() == v:false
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

    call leetcode#ShowSubmissions(slug)
endfunction

function! leetcode#ViewSubmissions()
    if leetcode#CheckSignIn() == v:false
        return
    endif
    " expand('%:t:r') returns the file name without the extension name
    let slug = expand('%:t:r')
    call leetcode#ShowSubmissions(slug)
endfunction

function! leetcode#ShowSubmissions(slug)
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
        setlocal nocursorline
        setlocal nobuflisted
        setlocal filetype=markdown
        nnoremap <silent> <buffer> <return> :call leetcode#ViewSubmission()<cr>

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

function! leetcode#ViewSubmission()
    if leetcode#CheckSignIn() == v:false
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

    " create the submission file in preview window
    call leetcode#CloseAnyPreview()
    let saved_winnr = winnr()
    execute 'rightbelow new '.subm['slug'].'.'.id.'.'.leetcode#SolutionFileExt(subm['filetype'])
    set modifiable

    " clear the buffer
    normal gg
    normal dG

    " show the submission description as comments
    let desc = leetcode#FormatResult(subm)
    call extend(desc, ['', '## Runtime Rank',
                \ '  - Faster than '.subm['runtime_rank'].' submissions'])
    let filetype = subm['filetype']
    let output = [leetcode#CommentStart(filetype, 'Submission '.id),
                \ leetcode#CommentLine(filetype, '')]
    for line in desc
        call add(output, leetcode#CommentLine(filetype, line))
    endfor
    call add(output, leetcode#CommentEnd(filetype))
    call append('$', output)
    call append('$', subm['code'])

    " delete the first line (it is a blank line)
    normal gg
    normal dd

    set nomodified
    set previewwindow

    execute saved_winnr.'wincmd w'
endfunction

function! leetcode#CloseAnyPreview()
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
