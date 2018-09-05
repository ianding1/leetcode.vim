let s:current_dir = expand("<sfile>:p:h")

python3 import vim
python3 if not vim.eval('s:current_dir') in sys.path: sys.path.append(vim.eval('s:current_dir'))
python3 import leetcode

let s:inited = py3eval('leetcode.inited')

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
        setlocal filetype=leetcode-list
        nnoremap <silent> <buffer> <return> :call leetcode#GoToProblem()<cr>
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

    let head = '| | #'.repeat(' ', max_id_len-1).' | Title'.repeat(' ', max_title_len-5).' | Accepted | Difficulty |'
    let separator= '|-| '.repeat('-', max_id_len).' | '.repeat('-', max_title_len).' | -------- | ---------- |'
    call append('$', [separator, head, separator])

    let format = '|%s| %-'.string(max_id_len).'d | %-'.string(max_title_len).'S | %8.1f%% | %-10S |'
    let output = []
    for p in problems
        call add(output, printf(format, p['state'], p['fid'], p['title'], p['ac_rate'] * 100, p['level']))
    endfor
    call append('$', output)

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
    execute 'rightbelow new '.problem['slug'].'.'.leetcode#SolutionFileExt()
    nnoremap <silent> <buffer> <f5> :call leetcode#TestSolution()<cr>
    nnoremap <silent> <buffer> <f6> :call leetcode#SubmitSolution()<cr>
    nnoremap <silent> <buffer> <f7> :call leetcode#ResetSolution()<cr>
    call leetcode#ResetSolution()

    " close the problem list
    let winnr = bufwinnr('LeetCode/List')
    if winnr != -1
        execute winnr.'hide'
    endif

    set nomodified
endfunction

function! leetcode#SolutionFileExt()
    let ft = g:leetcode_solution_filetype
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
    if type(problem) != v:t_dict
        return
    endif

    if !has_key(problem['templates'], &filetype)
        echo 'the solution file type is not supported'
        return
    endif

    " clear the buffer
    normal gg
    normal dG

    " show the problem description as comments
    let output = []
    call add(output, leetcode#CommentStart(&filetype, problem))
    call add(output, leetcode#CommentLine(&filetype, ''))
    for line in problem['desc']
        call add(output, leetcode#CommentLine(&filetype, line))
    endfor
    call extend(output, leetcode#CommentEnd(&filetype))
    call append('0', output)

    " wrap the long lines according to the option textwidth
    normal gg
    normal gqG

    " append the code template
    call append('$', problem['templates'][&filetype])
endfunction

function! leetcode#CommentStart(ft, problem)
    if index(['java', 'c', 'javascript', 'cpp', 'csharp', 'swift', 'scala', 'kotlin'], a:ft) >= 0
        let head = '/* '
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        let head = '# '
    elseif index(['golang'], a:ft) >= 0
        let head = '// '
    endif
    return head.a:problem['title'].' ['.a:problem['level'].'] [AC:'.
                \ printf('%s (%s of %s)', a:problem['ac_rate'],
                \ a:problem['total_accepted'], a:problem['total_submission']).
                \ '] [filetype:'.a:ft.']'
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
        return [' * Code:', ' */']
    elseif index(['python', 'python3', 'ruby'], a:ft) >= 0
        return '# Code:'
    elseif index(['golang'], a:ft) >= 0
        return '// Code:'
    else
        return ''
    endif
endfunction

function! leetcode#GuessFileType()
    " We first try figuring out the file type from the comment in the first
    " line. If we failed, we will try guessing it from the extension name.  We
    let first_line = getline(1)
    let file_type = matchstr(first_line, '\[filetype:[[:alpha:]]\+\]')
    if file_type
        return file_type[10:-2]
    endif

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
    endif
endfunction

function! leetcode#TestSolution()
    if leetcode#CheckSignIn() == v:false
        return
    endif

    " expand('%:t:r') returns the file name without the extension name
    let slug = expand('%:t:r')
    let file_type = leetcode#GuessFileType()
    let code = getline(1, '$')
    let result = py3eval('leetcode.test_solution("'.slug.'", "'.file_type.'")')
    if type(result) != v:t_dict
        return
    endif

    call leetcode#ShowResult(result)
endfunction

function! leetcode#SubmitSolution()
    if leetcode#CheckSignIn() == v:false
        return
    endif

    " expand('%:t:r') returns the file name without the extension name
    let slug = expand('%:t:r')
    let file_type = leetcode#GuessFileType()
    let code = getline(1, '$')
    let result = py3eval('leetcode.submit_solution("'.slug.'", "'.file_type.'")')
    if type(result) != v:t_dict
        return
    endif

    call leetcode#ShowResult(result)
endfunction

function! leetcode#ShowResult(result_)
    " the result is shown in a preview window, hence if there is already one,
    " we close it first
    pclose

    let saved_winnr = winnr()
    let result = a:result_
    rightbelow new LeetCode/Result
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal bufhidden=delete
    setlocal nospell
    setlocal nonumber
    setlocal norelativenumber
    setlocal nocursorline
    setlocal nobuflisted
    setlocal filetype=leetcode-result

    call append('$', 'Status: '.result['state'])
    call append('$', 'Runtime: '.result['runtime'])
    call append('$', 'Passed: '.result['passed'].' of '.result['total'])
    if len(result['testcase']) > 0
        call append('$', 'Test Case:')
        for tc in result['testcase']
            call append('$', '    '.tc)
        endfor
    endif
    if len(result['answer']) > 0
        call append('$', 'Actual Answer:')
        for ans in result['answer']
            call append('$', '    '.ans)
        endfor
    endif
    if len(result['expected_answer']) > 0
        call append('$', 'Expected Answer:')
        for ans in result['expected_answer']
            call append('$', '    '.ans)
        endfor
    endif
    if len(result['error']) > 0
        call append('$', 'Errors:')
        for err in result['error']
            call append('$', '    '.err)
        endfor
    endif
    if len(result['stdout']) > 0
        call append('$', 'Standard Output:')
        for err in result['stdout']
            call append('$', '  > '.err)
        endfor
    endif

    " go to the first line and delete it (it is a blank line)
    normal gg
    normal dd

    set previewwindow
    set nomodifiable
    set nomodified
    execute saved_winnr.'wincmd w'
endfunction
