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

    let expr = printf('leetcode.signin("%s", "%s")', username, password)
    let success = py3eval(expr)

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

function! s:SetupProblemListBuffer()
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

function! s:MaxWidthOfKey(list_of_dict, key, min_width)
    let max_width = a:min_width
    for item in a:list_of_dict
        let max_width = max([max_width, strwidth(item[a:key])])
    endfor
    return max_width
endfunction

function! s:PrintProblemList(problems)
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

function! s:ListProblemsOfTopic(topic_slug)
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

function! s:ListProblemsOfCompany(company_slug)
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

function! leetcode#ListProblems()
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

function! s:HandleProblemListCR()
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

function! s:SolutionFileExt(filetype)
    return s:file_type_to_ext[a:filetype]
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

function! s:HandleProblemListS()
    if line_nr >= b:leetcode_problem_start_line &&
                \ line_nr < b:leetcode_problem_end_line
        let problem_nr = line_nr - b:leetcode_problem_start_line
        let problem_slug = b:leetcode_problems[problem_nr]['slug']
        call s:ShowSubmissions(problem_slug)
    endif
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
            let id_width = strlen(s['id'])
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
