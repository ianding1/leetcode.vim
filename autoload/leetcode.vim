" vim: sts=4 sw=4 expandtab
if exists("g:leetcode_list_buffer_exists")
    echo 'buffer exists'
    finish
endif
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

function! s:LoadSessionCookie() abort
    if g:leetcode_browser ==# 'disabled'
       echo 'g:leetcode_browser is disabled.'
       return v:false
    endif

    let success = py3eval('leetcode.load_session_cookie("' . g:leetcode_browser . '")')
    if success
       echo 'Signed in.'
    endif
    return success
endfunction

function! leetcode#SignIn(ask) abort
    return s:LoadSessionCookie()
endfunction

function! s:CheckSignIn() abort
    if !py3eval('leetcode.is_login()')
        return leetcode#SignIn(0)
    endif
    return v:true
endfunction

function! s:SetupBasicSyntax() abort
    syn match lcHeader /\v^#{1,7} .*/

    hi! link lcHeader Title
endfunction

function! s:SetupProblemListBuffer() abort
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nobackup
    setlocal nonumber
    setlocal norelativenumber
    setlocal nospell
    setlocal bufhidden=hide
    setlocal nowrap
    nnoremap <silent> <buffer> <return> :call <SID>HandleProblemListCR()<cr>
    nnoremap <silent> <buffer> s :call <SID>HandleProblemListS()<cr>
    nnoremap <silent> <buffer> r :call <SID>HandleProblemListR()<cr>
    nnoremap <silent> <buffer> S :call <SID>HandleProblemListSort()<cr>

    call s:SetupBasicSyntax()

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

function! s:ProgressBar(percentile, width) abort
    let num_full_blocks = float2nr(ceil(a:percentile * a:width))
    let result = repeat('#', num_full_blocks)
    return printf('%-' . a:width . 'S', result)
endfunction

function! s:Max(values) abort
    let max_value = 0
    for value in a:values
        if value > max_value
            let max_value = value
        endif
    endfor
    return max_value
endfunction

let s:time_period_to_index_map = {'six-months': 0, 'one-year': 1,
            \ 'two-years': 2, 'all': 3}

let s:sort_column_to_name_map = {'state': 'Problem state',
            \ 'id': 'ID',
            \ 'title': 'Title',
            \ 'ac_rate': 'Accepted',
            \ 'level': 'Difficulty',
            \ 'frequency': 'Frequency'}

let s:sort_order_to_name_map = {'asc': 'From low to high',
            \ 'desc': 'From high to low'}

function! s:PrintProblemList() abort
    if exists('b:leetcode_time_period')
        let frequency_index = s:time_period_to_index_map[b:leetcode_time_period]
        for problem in b:leetcode_downloaded_problems
            let problem['frequency'] = problem['frequencies'][frequency_index]
        endfor
    endif

    let sorted_problems = leetcode#sort#SortProblems(
                \ b:leetcode_downloaded_problems,
                \ b:leetcode_sort_column)

    if b:leetcode_sort_order ==# 'desc'
        call reverse(sorted_problems)
    endif

    let b:leetcode_problems = sorted_problems

    let id_width = s:MaxWidthOfKey(sorted_problems, 'fid', 1)
    let title_width = s:MaxWidthOfKey(sorted_problems, 'title', 1) + 4
    let max_frequency = s:Max(map(copy(sorted_problems), 'v:val["frequency"]'))

    call append('$', [printf('## Difficulty [%s]', b:leetcode_difficulty), ''])
    let b:leetcode_difficulty_start_line = line('$')
    let difficulty_line = s:FormatIntoColumns(s:PrintDifficultyTags())
    call append('$', difficulty_line)
    let b:leetcode_difficulty_end_line = line('$')
    call append('$', '')

    call append('$', [printf('## Status [%s]', s:StateToName(b:leetcode_state)), ''])
    let b:leetcode_status_start_line = line('$')
    let status_line = s:FormatIntoColumns(s:PrintStatusTags())
    call append('$', status_line)
    let b:leetcode_status_end_line = line('$')
    call append('$', '')

    let sort_column_name = s:sort_column_to_name_map[b:leetcode_sort_column]
    let sort_order_name = s:sort_order_to_name_map[b:leetcode_sort_order]
    call append('$', ['## Problem List',
                \ '',
                \ '### Sorted by',
                \ '  Column:  ' . sort_column_name,
                \ '  Order:   ' . sort_order_name,
                \ '',
                \ '### Keys',
                \ '  <cr>  open the problem/go to the topic or company',
                \ '  s     view the submissions',
                \ '  r     refresh',
                \ '  S     sort by column',
                \ '',
                \ '### Indicators',
                \ '  [P]   paid-only problems',
                \ ''])

    let format = '|%1S| %-' . id_width . 'S | %-' . title_width .
                \ 'S | %-8S | %-10S | %-10S |'
    let header = printf(format, ' ', '#', 'Title', 'Accepted', 'Difficulty',
                \ 'Frequency')
    let separator = printf(format, '-', repeat('-', id_width),
                \ repeat('-', title_width), repeat('-', 8), repeat('-', 10),
                \ repeat('-', 10))

    call append('$', [header, separator])

    let problem_lines = []
    for problem in sorted_problems
        if b:leetcode_difficulty !=# 'All' && b:leetcode_difficulty !=# problem['level'] ||
                    \ b:leetcode_state !=# 'All' && b:leetcode_state !=# problem['state']
            continue
        endif
        let title = substitute(problem['title'], '`', "'", 'g')
        if problem['paid_only']
            let title .= ' [P]'
        endif
        call add(problem_lines, printf(format, problem['state'],
                    \ problem['fid'], title,
                    \ printf('%7.1f%%', problem['ac_rate'] * 100),
                    \ problem['level'],
                    \ s:ProgressBar(problem['frequency'] / max_frequency, 10)))
    endfor
    let b:leetcode_problem_start_line = line('$')
    call append('$', problem_lines)
    let b:leetcode_problem_end_line = line('$')
endfunction

function! s:PrintDifficultyTags()
    let tags = {'All': 0,  'Easy': 0, 'Medium': 0, 'Hard': 0}
    for problem in b:leetcode_problems
        let tags['All'] += 1
        let tags[problem['level']] += 1
    endfor
    return [
                \ printf('All:%d', tags['All']),
                \ printf('Easy:%d', tags['Easy']),
                \ printf('Medium:%d', tags['Medium']),
                \ printf('Hard:%d', tags['Hard'])]
endfunction

function! s:PrintStatusTags()
    let tags = {'All': 0, 'Todo': 0, 'Solved': 0, 'Attempted': 0}
    for problem in b:leetcode_problems
        let tags['All'] += 1
        let tags[s:StateToName(problem['state'])] += 1
    endfor
    return [
                \ printf('All:%d', tags['All']),
                \ printf('Todo:%d', tags['Todo']),
                \ printf('Solved:%d', tags['Solved']),
                \ printf('Attempted:%d', tags['Attempted'])]
endfunction

function! s:ListProblemsOfTopic(topic_slug, refresh) abort
    let buf_name = 'leetcode:///problems/topic/' . a:topic_slug
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        let saved_view = winsaveview()
        if a:refresh ==# 'redownload'
            let expr = printf('leetcode.get_problems_of_topic("%s")',
                        \ a:topic_slug)
            let b:leetcode_downloaded_problems = py3eval(expr)['problems']
        elseif a:refresh ==# 'norefresh'
            return
        endif
        setlocal modifiable
        silent! normal! ggdG
    else
        execute 'rightbelow new ' . buf_name
        call s:SetupProblemListBuffer()
        let b:leetcode_buffer_type = 'topic'
        let b:leetcode_buffer_topic = a:topic_slug
        let expr = printf('leetcode.get_problems_of_topic("%s")', a:topic_slug)
        let b:leetcode_downloaded_problems = py3eval(expr)['problems']
        let b:leetcode_difficulty = 'All'
        let b:leetcode_state = 'All'
        let b:leetcode_sort_column = 'id'
        let b:leetcode_sort_order = 'asc'
    endif

    let b:leetcode_topic_start_line = 0
    let b:leetcode_topic_end_line = 0
    let b:leetcode_company_start_line = 0
    let b:leetcode_company_end_line = 0

    setlocal modifiable

    call append('$', ['# LeetCode [topic:' . a:topic_slug . ']', ''])

    call s:PrintProblemList()

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only

    if exists('saved_view')
        call winrestview(saved_view)
    endif
endfunction

function! s:ChooseTimePeriod() abort
    let choice = inputlist(['Choose time period:',
                \ '1 - 6 months',
                \ '2 - 1 year',
                \ '3 - 2 years',
                \ '4 - all time'])
    if choice == 1
        let b:leetcode_time_period = 'six-months'
    elseif choice == 2
        let b:leetcode_time_period = 'one-year'
    elseif choice == 3
        let b:leetcode_time_period = 'two-years'
    elseif choice == 4
        let b:leetcode_time_period = 'all'
    else
        return
    endif
    call s:ListProblemsOfCompany(b:leetcode_buffer_company, 'redraw')
endfunction

function! s:ListProblemsOfCompany(company_slug, refresh) abort
    let bufname = 'leetcode:///problems/company/' . a:company_slug
    if buflisted(bufname)
        execute bufnr(bufname) . 'buffer'
        let saved_view = winsaveview()
        if a:refresh ==# 'redownload'
            let expr = printf('leetcode.get_problems_of_company("%s")',
                        \ a:company_slug)
            let b:leetcode_downloaded_problems = py3eval(expr)['problems']
        elseif a:refresh ==# 'norefresh'
            return
        endif
        setlocal modifiable
        silent! normal! ggdG
    else
        execute 'rightbelow new ' . bufname
        call s:SetupProblemListBuffer()
        let b:leetcode_buffer_type = 'company'
        let b:leetcode_buffer_company = a:company_slug
        let b:leetcode_time_period = 'six-months'
        nnoremap <buffer> t :call s:ChooseTimePeriod()<cr>

        let expr = printf('leetcode.get_problems_of_company("%s")',
                    \ a:company_slug)
        let b:leetcode_downloaded_problems = py3eval(expr)['problems']
        let b:leetcode_difficulty = 'All'
        let b:leetcode_state = 'All'
        let b:leetcode_sort_column = 'id'
        let b:leetcode_sort_order = 'asc'
    endif

    let b:leetcode_topic_start_line = 0
    let b:leetcode_topic_end_line = 0
    let b:leetcode_company_start_line = 0
    let b:leetcode_company_end_line = 0

    call append('$', ['# LeetCode [company:' . a:company_slug . ']',
                \ '',
                \ '## Frequency',
                \ '  Time period: ' . b:leetcode_time_period,
                \ '',
                \ '  t     choose time period',
                \ ''])

    call s:PrintProblemList()

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only

    if exists('saved_view')
        call winrestview(saved_view)
    endif
endfunction

function! leetcode#ListProblems(refresh) abort
    let buf_name = 'leetcode:///problems/all'
    if s:CheckSignIn() == v:false
        return
    endif
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        let saved_view = winsaveview()
        if a:refresh ==# 'redownload'
            let expr = 'leetcode.get_problems(["all"])'
            let b:leetcode_downloaded_problems = py3eval(expr)
        elseif a:refresh ==# 'norefresh'
            return
        endif
        setlocal modifiable
        silent! normal! ggdG
    else
        let g:leetcode_list_buffer_exists=1
        execute 'rightbelow new ' . buf_name
        call s:SetupProblemListBuffer()
        let b:leetcode_buffer_type = 'all'
        let expr = 'leetcode.get_problems(["all"])'
        let b:leetcode_downloaded_problems = py3eval(expr)
        let b:leetcode_difficulty = 'All'
        let b:leetcode_state = 'All'
        let b:leetcode_sort_column = 'id'
        let b:leetcode_sort_order = 'asc'
        let s:topics_and_companies = py3eval('leetcode.get_topics_and_companies()')
    endif

    let topics = s:topics_and_companies['topics']
    let companies = s:topics_and_companies['companies']

    " concatenate the topics into a string
    let topic_slugs = map(copy(topics), 'v:val["topic_slug"] . ":" . v:val["num_problems"]')
    let topic_lines = s:FormatIntoColumns(topic_slugs)

    call append('$', ['# LeetCode', '', '## Topics', ''])

    let b:leetcode_topic_start_line = line('$')
    call append('$', topic_lines)
    let b:leetcode_topic_end_line = line('$')

    let company_slugs = map(copy(companies), 'v:val["company_slug"] . ":" . v:val["num_problems"]')
    let company_lines = s:FormatIntoColumns(company_slugs)

    call append('$', ['', '## Companies', ''])

    let b:leetcode_company_start_line = line('$')
    call append('$', company_lines)
    let b:leetcode_company_end_line = line('$')

    call append('$', '')
    call s:PrintProblemList()

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only

    if exists('saved_view')
        call winrestview(saved_view)
    endif
endfunction

function! s:FileNameToSlug(file_name) abort
    return substitute(a:file_name, '_', '-', 'g')
endfunction

function! s:SlugToFileName(slug) abort
    return substitute(a:slug, '-', '_', 'g')
endfunction

function! s:HandleProblemListCR() abort
    " Parse the problem number from the line
    let line_nr = line('.')

    if line_nr >= b:leetcode_topic_start_line &&
                \ line_nr < b:leetcode_topic_end_line
        let topic_slug = expand('<cWORD>')
        let topic_slug = s:TagName(topic_slug)
        if topic_slug != ''
            call s:ListProblemsOfTopic(topic_slug, 'norefresh')
        endif
        return
    endif

    if line_nr >= b:leetcode_company_start_line &&
                \ line_nr < b:leetcode_company_end_line
        let company_slug = expand('<cWORD>')
        let company_slug = s:TagName(company_slug)
        if company_slug != ''
            call s:ListProblemsOfCompany(company_slug, 'norefresh')
        endif
        return
    endif

    if line_nr >= b:leetcode_difficulty_start_line &&
                \ line_nr < b:leetcode_difficulty_end_line
        let difficulty_slug = expand('<cWORD>')
        let difficulty_slug = s:TagName(difficulty_slug)
        if difficulty_slug != ''
            if b:leetcode_difficulty != difficulty_slug
                let b:leetcode_difficulty = difficulty_slug
                call s:RedrawProblemList()
            endif
        endif
    endif

    if line_nr >= b:leetcode_status_start_line &&
                \ line_nr < b:leetcode_status_end_line
        let status_slug = expand('<cWORD>')
        let status_slug = s:TagName(status_slug)
        if status_slug != ''
            let new_state = s:ParseState(status_slug)
            if b:leetcode_state != new_state
                let b:leetcode_state = new_state
                call s:RedrawProblemList()
            endif
        endif
    endif

    if line_nr >= b:leetcode_problem_start_line &&
                \ line_nr < b:leetcode_problem_end_line
        let problem_id = s:ProblemIdFromNr(line_nr)
        let problem = s:GetProblem(problem_id)
        let problem_slug = problem['slug']
        let problem_ext = s:SolutionFileExt(g:leetcode_solution_filetype)
        let problem_file_name = printf('%s.%s', s:SlugToFileName(problem_slug),
                    \ problem_ext)

        if buflisted(problem_file_name)
            execute bufnr(problem_file_name) . 'buffer'
            return
        endif

        execute 'rightbelow vnew ' . problem_file_name
        call leetcode#ResetSolution(1)
    endif
endfunction

function! s:ParseState(status)
    if a:status == 'Todo'
        return ' '
    elseif a:status == 'Solved'
        return 'X'
    elseif a:status == 'Attempted'
        return '?'
    else
        return 'All'
    endif
endfunction

function! s:StateToName(state)
    if a:state == ' '
        return 'Todo'
    elseif a:state == 'X'
        return 'Solved'
    elseif a:state == '?'
        return 'Attempted'
    else
        return 'All'
    endif
endfunction

function! s:RedrawProblemList()
    if b:leetcode_buffer_type ==# 'all'
        call leetcode#ListProblems('redraw')
    elseif b:leetcode_buffer_type ==# 'topic'
        call s:ListProblemsOfTopic(b:leetcode_buffer_topic, 'redraw')
    elseif b:leetcode_buffer_type ==# 'company'
        call s:ListProblemsOfCompany(b:leetcode_buffer_company, 'redraw')
    endif
endfunction

function! s:TagName(tag)
    return substitute(a:tag, ':\d*$', '', 'g')
endfunction

function! s:GetProblem(id)
    for problem in b:leetcode_downloaded_problems
        if problem['id'] == a:id
            return problem
        endif
    endfor
    return {}
endfunction

function! s:ProblemIdFromNr(nr)
    let content = getline(a:nr)
    let items = split(content, '|')
    if len(items) < 2
        return -1
    endif
    let strid = trim(items[1], ' ')
    return strid
endfunction

function! s:HandleProblemListR() abort
    if b:leetcode_buffer_type ==# 'all'
        call leetcode#ListProblems('redownload')
    elseif b:leetcode_buffer_type ==# 'topic'
        call s:ListProblemsOfTopic(b:leetcode_buffer_topic, 'redownload')
    elseif b:leetcode_buffer_type ==# 'company'
        call s:ListProblemsOfCompany(b:leetcode_buffer_company, 'redownload')
    endif
endfunction

let s:column_choice_map = {
            \ 1: 'state',
            \ 2: 'id',
            \ 3: 'title',
            \ 4: 'ac_rate',
            \ 5: 'level',
            \ 6: 'frequency'
            \ }

let s:order_choice_map = {1: 'asc', 2: 'desc'}

function! s:HandleProblemListSort() abort
    let column_choice = inputlist(['Sort by:',
                \ '1 - State',
                \ '2 - ID',
                \ '3 - Title',
                \ '4 - Accepted',
                \ '5 - Difficulty',
                \ '6 - Frequency'])
    if !(column_choice >= 1 && column_choice <= 6)
        return
    endif

    echo "\n"
    let order_choice = inputlist(['In which order:',
                \ '1 - From low to high',
                \ '2 - From high to low'])
    if order_choice != 1 && order_choice != 2
        return
    endif

    let b:leetcode_sort_column = s:column_choice_map[column_choice]
    let b:leetcode_sort_order = s:order_choice_map[order_choice]

    call s:RedrawProblemList()
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

    let problem_slug = s:FileNameToSlug(expand('%:t:r'))
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

    let file_name = s:FileNameToSlug(expand('%:t:r'))
    if file_name == ''
        echo 'no file name'
        return
    endif

    let slug = split(file_name, '\.')[0]
    let filetype = s:GuessFileType()

    if exists('b:leetcode_problem')
        let problem = b:leetcode_problem
    else
        let problem = py3eval(printf('leetcode.get_problem("%s")', slug))
        let b:leetcode_problem = problem
    endif

    if !problem['testable']
        echomsg 'the problem is not testable'
        return
    endif

    let code = join(getline('1', '$'), "\n")

    call s:AskTestInputAndRunTest(problem, filetype, code)
endfunction

let s:saved_test_input = {}

function! s:AskTestInputAndRunTest(problem, filetype, code) abort
    execute 'rightbelow new ' . tempname()
    setlocal noswapfile
    setlocal nobackup
    setlocal bufhidden=delete
    setlocal nospell
    setlocal nobuflisted

    syn match TestInputComment /\v^#.*/
    hi! link TestInputComment Comment

    let slug = a:problem['slug']

    if has_key(s:saved_test_input, slug)
        let default_test_input = s:saved_test_input[slug]
    else
        let default_test_input = ['# Test Input'] +
                    \ split(a:problem['testcase'], '\n', 1)
        let s:saved_test_input[slug] = default_test_input
    endif

    call append('$', default_test_input)

    silent! normal! ggdd

    let s:leetcode_problem = a:problem
    let s:leetcode_code = a:code
    let s:leetcode_filetype = a:filetype

    autocmd BufUnload <buffer> call s:RunTest()
endfunction

let s:comment_pattern = '\v(^#.*)|(^\s*$)'

function! s:RunTest() abort
    let problem = s:leetcode_problem
    let code = s:leetcode_code
    let filetype = s:leetcode_filetype

    " Load the buffer from the disk. If the user executed :q!, the buffer
    " will be cleared since the file is empty.
    edit!

    let raw_test_input = getline('1', '$')
    let test_input = filter(copy(raw_test_input), 'v:val !~# s:comment_pattern')
    let test_input = join(test_input, "\n")

    if test_input == ''
        echo 'Abort testing because the test input is empty'
        return
    endif

    let s:saved_test_input[problem['slug']] = raw_test_input

    let args = {'problem_id': problem['id'],
                \ 'title': problem['title'],
                \ 'slug': problem['slug'],
                \ 'filetype': filetype,
                \ 'code': code,
                \ 'test_input': test_input}

    if has('timers')
        let ok = py3eval('leetcode.test_solution_async(**vim.eval("args"))')
        if ok
            call timer_start(200, function('s:CheckRunCodeTask'),
                        \ {'repeat': -1})
        endif
    else
        let result = py3eval('leetcode.test_solution(**vim.eval("args"))')
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

    let file_name = s:FileNameToSlug(expand('%:t:r'))
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
    setlocal modifiable

    let output = s:FormatResult(a:result)
    call append('$', output)

    silent! normal! ggdd

    setlocal previewwindow
    setlocal nomodifiable
    setlocal nomodified

    call s:SetupBasicSyntax()

    " add custom syntax rules
    syn keyword lcAccepted Accepted
    syn keyword lcAccepted Finished
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
    call s:UpdateSubmitState(a:result)
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
        let problem_id = s:ProblemIdFromNr(line_nr)
        let problem = s:GetProblem(problem_id)
        let problem_slug = problem['slug']
        call s:ListSubmissions(problem_slug, 0)
    endif
endfunction

function! s:ListSubmissions(slug, refresh) abort
    let buf_name = 'leetcode:///submissions/' . a:slug
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        if a:refresh
            setlocal modifiable
            silent! normal! ggdG
        else
            return
        endif
    else
        execute 'rightbelow new ' . buf_name
        setlocal buftype=nofile
        setlocal noswapfile
        setlocal nobackup
        setlocal bufhidden=hide
        setlocal nospell
        setlocal nonumber
        setlocal norelativenumber
        setlocal nowrap
        nnoremap <silent> <buffer> <return> :call <SID>HandleSubmissionsCR()<cr>
        nnoremap <silent> <buffer> r :call <SID>HandleSubmissionsRefresh()<cr>

        call s:SetupBasicSyntax()

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
    endif

    let b:leetcode_problem_slug = a:slug

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

    let time_width = s:MaxWidthOfKey(submissions, 'time', 4)
    let id_width = s:MaxWidthOfKey(submissions, 'id', 2)
    let runtime_width = s:MaxWidthOfKey(submissions, 'runtime', 7)

    let output = []
    call add(output, '# '.problem['title'])
    call add(output, '')
    call add(output, '## Submissions')
    call add(output, '  <cr>  view submission')
    call add(output, '  r     refresh')
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

    let file_name = printf('%s.%s.%s', s:SlugToFileName(submission['slug']),
                \ submission_id, s:SolutionFileExt(submission['filetype']))

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

function! s:HandleSubmissionsRefresh() abort
    call s:ListSubmissions(b:leetcode_problem_slug, 1)
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
    if num_rows == 0
        let num_rows = 1
    endif
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

function! s:UpdateSubmitState(result)
    let state = '?'
    if a:result['state'] ==# 'Accepted'
        let state = 'X'
    endif
    let buffers = filter(range(1, bufnr('$')), 'buflisted(v:val)')
    for b in buffers
        let name = bufname(b)
        if name !~# 'leetcode:\/\/\/problems'
            continue
        endif

        let problems = getbufvar(b, 'leetcode_downloaded_problems')
        if type(problems) != v:t_list
            continue
        endif

        for problem in problems
            if problem['title'] ==# a:result['title']
                let problem['state'] = state
                break
            endif
        endfor
    endfor
endfunction
