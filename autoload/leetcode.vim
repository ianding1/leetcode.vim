" vim: sts=4 sw=4 expandtab
scriptencoding utf-8
if exists('g:leetcode_list_buffer_exists')
    echo 'buffer exists'
    finish
endif
let s:current_dir = expand('<sfile>:p:h')

if !empty(get(g:, 'leetcode_base_url', ''))
    let s:base_url = substitute(g:leetcode_base_url, '/\+$', '', '')
elseif g:leetcode_china
    let s:base_url = 'https://leetcode.cn'
else
    let s:base_url = 'https://leetcode.com'
endif
let s:host = matchstr(s:base_url, '://\zs[^/]\+')

" Which implementation of the LeetCode API to use:
"   'vim'     autoload/leetcode/api.vim (needs curl, no Python); the default
"   'python'  autoload/leetcode.py (needs +python3 with requests)
" Reading cookies from a browser's store needs Python, so a config that asks
" for that keeps the Python backend unless it picks one.
let s:backend = get(g:, 'leetcode_backend',
            \ index(['chrome', 'firefox'], get(g:, 'leetcode_browser', '')) >= 0 ? 'python' : 'vim')

if s:backend ==# 'vim'
    let s:inited = 1
    call leetcode#api#Init(s:base_url)
elseif has('python3')
    python3 import os, sys, vim
    python3 sys.path.append(vim.eval('s:current_dir')) if vim.eval('s:current_dir') not in sys.path else None
    python3 os.environ['LEETCODE_BASE_URL'] = vim.eval('s:base_url')
    python3 import leetcode
    let s:inited = py3eval('leetcode.inited')
    if g:leetcode_debug
        python3 leetcode.enable_logging()
    endif
else
    let s:inited = 0
endif

function! s:ReportMissingDependencies() abort
    echohl ErrorMsg
    if !has('python3')
        echomsg printf('leetcode.vim: %s has no Python 3 support. Set g:leetcode_backend '
                    \ . 'to ''vim'' (needs curl), or use %s.', has('nvim') ? 'Neovim' : 'this Vim',
                    \ has('nvim') ? 'pip install pynvim' : 'a Vim with +python3')
    else
        let py_version = py3eval('"%d.%d" % sys.version_info[:2]')
        echomsg printf('leetcode.vim: %s. Install the dependencies for the Python %s '
                    \ . 'that Vim uses: python%s -m pip install --user requests',
                    \ py3eval('leetcode.import_error'), py_version, py_version)
    endif
    echohl None
endfunction

if !s:inited
    call s:ReportMissingDependencies()
endif

let s:python_names = {
            \ 'IsLogin': 'is_login',
            \ 'StartSessionWithCookies': 'start_session_with_cookies',
            \ 'GetProgress': 'get_progress',
            \ 'GetProblems': 'get_problems',
            \ 'GetProblem': 'get_problem',
            \ 'GetProblemsOfTopic': 'get_problems_of_topic',
            \ 'GetProblemsOfCompany': 'get_problems_of_company',
            \ 'GetTopicsAndCompanies': 'get_topics_and_companies',
            \ 'GetSubmissions': 'get_submissions',
            \ 'GetSubmission': 'get_submission',
            \ }

" Call the LeetCode API function `name` of the selected backend.
function! leetcode#Api(name, ...) abort
    if s:backend ==# 'vim'
        return call('leetcode#api#' . a:name, a:000)
    endif
    let l:args = a:000
    return py3eval(printf('leetcode.%s(*vim.eval("l:args"))', s:python_names[a:name]))
endfunction

" Whether a test run or submission is still in progress.
function! leetcode#Busy() abort
    if s:backend ==# 'vim'
        return !empty(leetcode#api#TaskName())
    endif
    return !empty(filter(timer_info(), 'string(v:val.callback) =~# "CheckRunCodeTask"'))
endfunction

function! leetcode#BaseUrl() abort
    return s:base_url
endfunction

function! s:StartSession(cookies) abort
    return leetcode#Api('StartSessionWithCookies', a:cookies) ? v:true : v:false
endfunction

function! s:EnvSignIn() abort
    let cookies = {'LEETCODE_SESSION': $LEETCODE_SESSION, 'csrftoken': $LEETCODE_CSRFTOKEN}
    if empty(cookies.LEETCODE_SESSION)
        echomsg '$LEETCODE_SESSION is not set. Copy the LEETCODE_SESSION (and csrftoken) '
                    \ . 'cookie from your browser into $LEETCODE_SESSION (and $LEETCODE_CSRFTOKEN).'
        return v:false
    endif
    if !s:StartSession(cookies)
        echomsg 'cannot get progress. Please update $LEETCODE_SESSION.'
        return v:false
    endif
    return v:true
endfunction

" Sign in with a saved cookie, or ask for one. With `ask`, always ask, so
" :LeetCodeSignIn can replace the saved cookie (e.g. to switch accounts).
function! s:PasteSignIn(ask) abort
    if !a:ask
        let saved = leetcode#auth#Load(s:host)
        if !empty(saved)
            if s:StartSession(saved)
                return v:true
            endif
            call leetcode#auth#Save(s:host, {})
            echohl WarningMsg
            echomsg 'leetcode.vim: the saved LeetCode session has expired. Please paste a new cookie.'
            echohl None
        endif
    endif

    let text = inputsecret(printf('Cookie from a browser signed in to %s '
                \ . '(see :help leetcode-sign-in): ', s:host))
    redraw
    let cookies = leetcode#auth#ParseCookie(text)
    if empty(cookies)
        echo 'Sign-in cancelled.'
        return v:false
    endif
    if !has_key(cookies, 'LEETCODE_SESSION')
        echohl ErrorMsg
        echomsg 'leetcode.vim: no LEETCODE_SESSION in the pasted cookie.'
        echohl None
        return v:false
    endif
    if !s:StartSession(cookies)
        echohl ErrorMsg
        echomsg 'leetcode.vim: LeetCode did not accept this cookie. '
                    \ . 'Is it from a signed-in browser, and complete?'
        echohl None
        return v:false
    endif
    call leetcode#auth#Save(s:host, cookies)
    return v:true
endfunction

function! leetcode#SignIn(ask) abort
    if !s:inited
        call s:ReportMissingDependencies()
        return v:false
    endif
    if g:leetcode_browser ==# 'env'
        let success = s:EnvSignIn()
    elseif index(['chrome', 'firefox'], g:leetcode_browser) >= 0
        if s:backend ==# 'vim'
            echomsg printf('leetcode.vim: reading cookies from %s needs g:leetcode_backend = '
                        \ . '''python''. Use g:leetcode_browser = ''paste'' instead.', g:leetcode_browser)
            return v:false
        endif
        let success = py3eval('leetcode.load_session_cookie("' . g:leetcode_browser . '")')
    else
        let success = s:PasteSignIn(a:ask)
    endif
    if success
        echo 'Signed in.'
    endif
    return success
endfunction

function! leetcode#SignOut() abort
    call leetcode#auth#Save(s:host, {})
    if s:backend ==# 'vim'
        call leetcode#api#SignOut()
    elseif s:inited
        python3 leetcode.session = None
    endif
    echo 'Signed out.'
endfunction

function! s:CheckSignIn() abort
    if !s:inited
        call s:ReportMissingDependencies()
        return v:false
    endif
    if !leetcode#Api('IsLogin')
        return leetcode#SignIn(0)
    endif
    return v:true
endfunction

function! s:SetupBasicSyntax() abort
    syn match lcHeader /\v^#{1,7} .*/
endfunction

" Colors for the plugin's buffers. `hi def` leaves alone whatever your vimrc
" or colorscheme sets for these groups. Neovim's diagnostic colors follow the
" colorscheme; in Vim the colors suit 'background'.
function! s:DefineHighlights() abort
    if hlexists('DiagnosticOk')
        hi def link lcEasy DiagnosticOk
        hi def link lcMedium DiagnosticWarn
        hi def link lcHard DiagnosticError
        hi def link lcAccepted DiagnosticOk
        hi def link lcFailure DiagnosticError
    else
        let light = &background ==# 'light'
        execute 'hi def lcEasy ctermfg=' . (light ? 'darkgreen guifg=#1a7f37' : 'lightgreen guifg=#7ee787')
        execute 'hi def lcMedium ctermfg=' . (light ? 'brown guifg=#9a6700' : 'yellow guifg=#e3b341')
        execute 'hi def lcHard ctermfg=' . (light ? 'darkred guifg=#cf222e' : 'red guifg=#ff7b72')
        execute 'hi def lcAccepted term=bold cterm=bold gui=bold ctermfg='
                    \ . (light ? 'darkgreen guifg=#1a7f37' : 'lightgreen guifg=#7ee787')
        execute 'hi def lcFailure term=bold cterm=bold gui=bold ctermfg='
                    \ . (light ? 'darkred guifg=#cf222e' : 'red guifg=#ff7b72')
    endif
    hi def link lcHeader Title
    hi def link lcDone lcEasy
    hi def link lcTodo lcMedium
    hi def link lcPaidOnly lcMedium
    hi def link lcOK lcAccepted
    hi def link lcWarning lcFailure
    hi def link lcNA Comment
    hi def link lcMismatch DiffText
    hi def link TestInputComment Comment
endfunction

call s:DefineHighlights()
augroup leetcode_highlights
    autocmd!
    autocmd ColorScheme * call s:DefineHighlights()
augroup END

" How a problem's status is shown in the list: solved, attempted, to do.
let s:status_marks = &encoding ==# 'utf-8'
            \ ? {'X': '✓', '?': '~', ' ': ' '} : {'X': 'X', '?': '?', ' ': ' '}

" `text` cut to `width` display cells, ending in an ellipsis when cut.
function! s:Truncate(text, width) abort
    if strdisplaywidth(a:text) <= a:width
        return a:text
    endif
    let ellipsis = &encoding ==# 'utf-8' ? '…' : '...'
    let text = a:text
    while strdisplaywidth(text) > a:width - strdisplaywidth(ellipsis)
        let text = strcharpart(text, 0, strchars(text) - 1)
    endwhile
    return substitute(text, '\s\+$', '', '') . ellipsis
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
    nnoremap <silent> <buffer> f :call <SID>HandleProblemListFilter()<cr>
    nnoremap <silent> <buffer> F :call <SID>HandleProblemListClearFilter()<cr>

    call s:SetupBasicSyntax()

    syn match lcEasy /| Easy /hs=s+2
    syn match lcMedium /| Medium /hs=s+2
    syn match lcHard /| Hard /hs=s+2
    execute 'syn match lcDone /^|\V' . s:status_marks['X'] . '\m|/hs=s+1,he=e-1'
    execute 'syn match lcTodo /^|\V' . s:status_marks['?'] . '\m|/hs=s+1,he=e-1'
    syn match lcPaidOnly /\[P\]/
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
    if g:leetcode_hide_paid_only
        call filter(b:leetcode_problems, 'v:val["paid_only"] == 0')
    endif

    let id_width = s:MaxWidthOfKey(sorted_problems, 'fid', 1)
    " [P] takes 4 more cells; very long titles are cut.
    let title_width = min([s:MaxWidthOfKey(sorted_problems, 'title', 1) + 4, 64])
    let max_frequency = s:Max(map(copy(sorted_problems), 'v:val["frequency"]'))

    call append('$', printf('## Difficulty [%s]', b:leetcode_difficulty))
    let b:leetcode_difficulty_start_line = line('$')
    let difficulty_line = s:FormatIntoColumns(s:PrintDifficultyTags())
    call append('$', difficulty_line)
    let b:leetcode_difficulty_end_line = line('$')
    call append('$', '')

    call append('$', printf('## Status [%s]', s:StateToName(b:leetcode_state)))
    let b:leetcode_status_start_line = line('$')
    let status_line = s:FormatIntoColumns(s:PrintStatusTags())
    call append('$', status_line)
    let b:leetcode_status_end_line = line('$')
    call append('$', '')

    let shown = filter(copy(sorted_problems),
                \ '(b:leetcode_difficulty ==# "All" || b:leetcode_difficulty ==# v:val.level)'
                \ . ' && (b:leetcode_state ==# "All" || b:leetcode_state ==# v:val.state)'
                \ . ' && s:MatchesFilter(v:val)')
    let filter_text = get(b:, 'leetcode_filter', '')
    let sort_column_name = s:sort_column_to_name_map[b:leetcode_sort_column]
    let sort_order_name = s:sort_order_to_name_map[b:leetcode_sort_order]
    call append('$', [printf('## Problem List (%d shown%s, sorted by %s, %s)', len(shown),
                \ empty(filter_text) ? '' : ', filter "' . filter_text . '"',
                \ sort_column_name, tolower(sort_order_name)),
                \ '  <CR> open   s submissions   S sort   f filter'
                \ . (empty(filter_text) ? '' : '   F clear filter') . '   r refresh'
                \ . (get(b:, 'leetcode_buffer_type', '') ==# 'company' ? '   t time period' : '')
                \ . (get(b:, 'leetcode_buffer_type', '') ==# 'all' ? '   zo/zc topics & companies' : ''),
                \ printf('  %s solved   %s attempted   [P] paid-only',
                \   s:status_marks['X'], s:status_marks['?']),
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
    for problem in shown
        let title = substitute(problem['title'], '`', "'", 'g')
        if problem['paid_only']
            let title = s:Truncate(title, title_width - 4) . ' [P]'
        else
            let title = s:Truncate(title, title_width)
        endif
        call add(problem_lines, printf(format, get(s:status_marks, problem['state'], ' '),
                    \ problem['fid'], title,
                    \ printf('%7.1f%%', problem['ac_rate'] * 100),
                    \ problem['level'],
                    \ s:ProgressBar(problem['frequency'] / max_frequency, 10)))
    endfor
    let b:leetcode_problem_start_line = line('$')
    call append('$', problem_lines)
    let b:leetcode_problem_end_line = line('$')
endfunction

function! s:PrintDifficultyTags() abort
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

function! s:PrintStatusTags() abort
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
            let b:leetcode_downloaded_problems =
                        \ leetcode#Api('GetProblemsOfTopic', a:topic_slug)['problems']
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
        let b:leetcode_downloaded_problems =
                    \ leetcode#Api('GetProblemsOfTopic', a:topic_slug)['problems']
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
    else
        call cursor(b:leetcode_problem_start_line, 1)
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
            let b:leetcode_downloaded_problems =
                        \ leetcode#Api('GetProblemsOfCompany', a:company_slug)['problems']
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
        nnoremap <silent> <buffer> t :call <SID>ChooseTimePeriod()<cr>

        let b:leetcode_downloaded_problems =
                    \ leetcode#Api('GetProblemsOfCompany', a:company_slug)['problems']
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
                \ '  Frequency over: ' . b:leetcode_time_period,
                \ ''])

    call s:PrintProblemList()

    silent! normal! ggdd
    setlocal nomodifiable
    silent! only

    if exists('saved_view')
        call winrestview(saved_view)
    else
        call cursor(b:leetcode_problem_start_line, 1)
    endif
endfunction

function! leetcode#ListProblems(refresh) abort
    let buf_name = 'leetcode:///problems/' . g:leetcode_problemset
    if s:CheckSignIn() == v:false
        return
    endif
    if buflisted(buf_name)
        execute bufnr(buf_name) . 'buffer'
        let saved_view = winsaveview()
        if a:refresh ==# 'redownload'
            let b:leetcode_downloaded_problems =
                        \ leetcode#Api('GetProblems', [g:leetcode_problemset])
        elseif a:refresh ==# 'norefresh'
            return
        endif
        call s:RememberOpenSections()
        setlocal modifiable
        silent! normal! ggdG
    else
        let g:leetcode_list_buffer_exists=1
        execute 'rightbelow new ' . buf_name
        call s:SetupProblemListBuffer()
        let b:leetcode_buffer_type = 'all'
        let b:leetcode_downloaded_problems =
                    \ leetcode#Api('GetProblems', [g:leetcode_problemset])
        let b:leetcode_difficulty = 'All'
        let b:leetcode_state = 'All'
        let b:leetcode_sort_column = 'id'
        let b:leetcode_sort_order = 'asc'
        let s:topics_and_companies = leetcode#Api('GetTopicsAndCompanies')
    endif

    let topics = s:topics_and_companies['topics']
    let companies = s:topics_and_companies['companies']

    call append('$', ['# LeetCode', ''])

    let b:leetcode_topic_start_line = 0
    let b:leetcode_topic_end_line = 0
    if g:leetcode_hide_topics == 0 && !empty(topics)
        let topic_slugs = map(copy(topics), 'v:val["topic_slug"] . ":" . v:val["num_problems"]')
        call append('$', printf('## Topics (%d)', len(topics)))
        let b:leetcode_topic_start_line = line('$')
        call append('$', s:FormatIntoColumns(topic_slugs))
        let b:leetcode_topic_end_line = line('$')
        call append('$', '')
    endif

    let b:leetcode_company_start_line = 0
    let b:leetcode_company_end_line = 0
    if g:leetcode_hide_companies == 0 && !empty(companies)
        let company_slugs = map(copy(companies), 'v:val["company_slug"] . ":" . v:val["num_problems"]')
        call append('$', printf('## Companies (%d)', len(companies)))
        let b:leetcode_company_start_line = line('$')
        call append('$', s:FormatIntoColumns(company_slugs))
        let b:leetcode_company_end_line = line('$')
        call append('$', '')
    endif

    call s:PrintProblemList()

    silent! normal! ggdd
    call s:FoldSections()
    setlocal nomodifiable
    silent! only

    if exists('saved_view')
        call winrestview(saved_view)
    else
        call cursor(b:leetcode_problem_start_line, 1)
    endif
endfunction

" Topics and companies are long lists: keep each in a fold, closed until
" opened, and remember which ones are open across redraws.
function! s:FoldSections() abort
    let open = get(b:, 'leetcode_open_sections', {})
    setlocal foldmethod=manual foldtext=leetcode#ListFoldText() foldenable
    normal! zE
    for [name, last] in [['Topics', b:leetcode_topic_end_line - 1],
                \ ['Companies', b:leetcode_company_end_line - 1]]
        let first = search('^## ' . name . ' (', 'nw')
        if first > 0 && last > first
            execute first . ',' . last . 'fold'
            if get(open, name, 0)
                execute first . 'foldopen'
            endif
        endif
    endfor
endfunction

function! s:RememberOpenSections() abort
    let b:leetcode_open_sections = {}
    for name in ['Topics', 'Companies']
        let first = search('^## ' . name . ' (', 'nw')
        let b:leetcode_open_sections[name] = first > 0 && foldclosed(first) == -1
    endfor
endfunction

function! leetcode#ListFoldText() abort
    return substitute(getline(v:foldstart), '^## ', '+ ', '') . '   <CR> to expand'
endfunction

function! s:FileNameToSlug(file_name) abort
    return substitute(a:file_name, '_', '-', 'g')
endfunction

function! s:SlugToFileName(slug) abort
    return substitute(a:slug, '-', '_', 'g')
endfunction

function! s:ProblemSlugFromFileName() abort
    if exists('b:leetcode_slug')
        return b:leetcode_slug
    endif
    let parts = split(expand('%:t:r'), '\.')  " Filename without the extension
    if len(parts) == 1
        " Old style, e.g. two-sum
        return s:FileNameToSlug(parts[0])
    elseif len(parts) == 2 && parts[0] =~# '\v^[0-9]+$'
        " New style, e.g. 1.two-sum
        return s:FileNameToSlug(parts[1])
    elseif len(parts) == 2
        if parts[-1] =~# '^\d\+$'
            " Old style with submission id, e.g. two-sum.1234 
            return s:FileNameToSlug(parts[0])
        else
            " There some problems like `面试题59 - II.dui_lie_de_zui_da_zhi_lcof.cpp` in leetcode-cn
            return s:FileNameToSlug(parts[-1])
        endif
    elseif len(parts) == 3
        if parts[-1] =~# '^\d\+$'
            " New style with submission id, e.g. 1.two-sum.1234
            return s:FileNameToSlug(parts[1])
        else
            " There some problems like `面试题 02.06.palindrome_linked_list_lcci.cpp` in leetcode-cn
            return s:FileNameToSlug(parts[-1])
        endif
    else
        throw 'leetcode: invalid file name: ' . expand('%:t:r')
    endif
endfunction

function! s:HandleProblemListCR() abort
    if foldclosed('.') != -1
        normal! zo
        return
    endif
    " Parse the problem number from the line
    let line_nr = line('.')

    if line_nr >= get(b:, 'leetcode_topic_start_line', 0) &&
                \ line_nr < get(b:, 'leetcode_topic_end_line', 0)
        let topic_slug = expand('<cWORD>')
        let topic_slug = s:TagName(topic_slug)
        if topic_slug !=# ''
            call s:ListProblemsOfTopic(topic_slug, 'redraw')
        endif
        return
    endif

    if line_nr >= get(b:, 'leetcode_company_start_line', 0) &&
                \ line_nr < get(b:, 'leetcode_company_end_line', 0)
        let company_slug = expand('<cWORD>')
        let company_slug = s:TagName(company_slug)
        if company_slug !=# ''
            call s:ListProblemsOfCompany(company_slug, 'redraw')
        endif
        return
    endif

    if line_nr >= b:leetcode_difficulty_start_line &&
                \ line_nr < b:leetcode_difficulty_end_line
        let difficulty_slug = expand('<cWORD>')
        let difficulty_slug = s:TagName(difficulty_slug)
        if difficulty_slug !=# ''
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
        if status_slug !=# ''
            let new_state = s:ParseState(status_slug)
            if b:leetcode_state != new_state
                let b:leetcode_state = new_state
                call s:RedrawProblemList()
            endif
        endif
    endif

    if line_nr >= b:leetcode_problem_start_line &&
                \ line_nr < b:leetcode_problem_end_line
        call s:OpenProblem(s:GetProblem(s:ProblemIdFromNr(line_nr)))
    endif
endfunction

" Open the solution file of `problem`, with its description above. An empty
" window is reused; otherwise the solution opens in a new one on the right.
function! s:OpenProblem(problem) abort
    if empty(a:problem)
        return
    endif
    let path = s:SolutionPath(a:problem)
    let nr = bufnr(path)
    if nr > 0 && buflisted(nr)
        execute nr . 'buffer'
        return
    endif
    let is_new = !filereadable(path)
    let name = fnameescape(fnamemodify(path, ':~:.'))
    if empty(bufname('%')) && !&modified && line('$') == 1 && empty(getline(1))
        execute 'edit ' . name
    else
        execute 'rightbelow vnew ' . name
    endif
    if !is_new
        " Your file: open it as it is (:LeetCodeReset starts over).
        if s:CheckSignIn() == v:false
            return
        endif
        let b:leetcode_slug = a:problem['slug']
        let problem = leetcode#Api('GetProblem', a:problem['slug'])
        if type(problem) == v:t_dict
            call s:ShowDescription(problem)
        endif
        return
    endif
    call leetcode#ResetSolution(1)
    if exists('b:leetcode_slug')
        " Saved right away, so there is nothing to lose and nothing to ask.
        call mkdir(fnamemodify(path, ':h'), 'p')
        silent write
        echo 'Solution saved to ' . fnamemodify(path, ':~')
    endif
endfunction

" Where the solution of `problem` lives: in g:leetcode_solution_dir
" (default ~/leetcode), or the current directory when that is empty.
function! s:SolutionPath(problem) abort
    let dir = empty(g:leetcode_solution_dir) ? getcwd() : expand(g:leetcode_solution_dir)
    " :p ends in a slash only when the directory exists.
    let dir = substitute(fnamemodify(dir, ':p'), '[/\\]\=$', '/', '')
    return dir . printf('%s.%s.%s', a:problem['fid'],
                \ s:SlugToFileName(a:problem['slug']), s:SolutionFileExt(g:leetcode_solution_filetype))
endfunction

" All problems: those of an open problem list, or downloaded once.
function! s:AllProblems(download) abort
    let list = bufnr('leetcode:///problems/' . g:leetcode_problemset)
    let problems = list > 0 ? getbufvar(list, 'leetcode_downloaded_problems', []) : []
    if type(problems) == v:t_list && !empty(problems)
        return problems
    endif
    if !exists('s:all_problems') && a:download
        let problems = leetcode#Api('GetProblems', [g:leetcode_problemset])
        if type(problems) == v:t_list && !empty(problems)
            let s:all_problems = problems
        endif
    endif
    return get(s:, 'all_problems', [])
endfunction

" :LeetCodeOpen 1, :LeetCodeOpen two-sum
function! leetcode#OpenProblem(name) abort
    if s:CheckSignIn() == v:false
        return
    endif
    let name = trim(a:name)
    for problem in s:AllProblems(1)
        if problem['fid'] ==# name || problem['slug'] ==# name
            call s:OpenProblem(problem)
            return
        endif
    endfor
    echohl ErrorMsg
    echomsg 'leetcode.vim: no problem ' . string(name) . ' (give its number or slug)'
    echohl None
endfunction

" Signed in, or signs in with the saved session; never asks for a cookie.
function! s:QuietSignIn() abort
    if !s:inited
        return v:false
    endif
    if leetcode#Api('IsLogin')
        return v:true
    endif
    let saved = g:leetcode_browser ==# 'paste' ? leetcode#auth#Load(s:host) : {}
    return !empty(saved) && s:StartSession(saved)
endfunction

" Completes slugs. It never asks to sign in: without a session it only knows
" the problems of an open list.
function! leetcode#CompleteProblem(arg_lead, cmd_line, cursor_pos) abort
    let problems = s:AllProblems(s:QuietSignIn())
    return filter(map(copy(problems), 'v:val["slug"]'), 'stridx(v:val, a:arg_lead) == 0')
endfunction

function! s:MatchesFilter(problem) abort
    let text = get(b:, 'leetcode_filter', '')
    return empty(text) || a:problem['fid'] ==# text
                \ || stridx(tolower(a:problem['title']), tolower(text)) >= 0
endfunction

function! s:HandleProblemListFilter() abort
    let text = trim(input('Filter by title or number: ', get(b:, 'leetcode_filter', '')))
    let b:leetcode_filter = text
    call s:RedrawProblemList()
    call cursor(b:leetcode_problem_start_line, 1)
endfunction

function! s:HandleProblemListClearFilter() abort
    if !empty(get(b:, 'leetcode_filter', ''))
        let b:leetcode_filter = ''
        call s:RedrawProblemList()
        call cursor(b:leetcode_problem_start_line, 1)
    endif
endfunction

function! s:ParseState(status) abort
    if a:status ==# 'Todo'
        return ' '
    elseif a:status ==# 'Solved'
        return 'X'
    elseif a:status ==# 'Attempted'
        return '?'
    else
        return 'All'
    endif
endfunction

function! s:StateToName(state) abort
    if a:state ==# ' '
        return 'Todo'
    elseif a:state ==# 'X'
        return 'Solved'
    elseif a:state ==# '?'
        return 'Attempted'
    else
        return 'All'
    endif
endfunction

function! s:RedrawProblemList() abort
    if b:leetcode_buffer_type ==# 'all'
        call leetcode#ListProblems('redraw')
    elseif b:leetcode_buffer_type ==# 'topic'
        call s:ListProblemsOfTopic(b:leetcode_buffer_topic, 'redraw')
    elseif b:leetcode_buffer_type ==# 'company'
        call s:ListProblemsOfCompany(b:leetcode_buffer_company, 'redraw')
    endif
endfunction

function! s:TagName(tag) abort
    return substitute(a:tag, ':\d*$', '', 'g')
endfunction

function! s:GetProblem(id) abort
    for problem in b:leetcode_downloaded_problems
        if problem['fid'] == a:id
            return problem
        endif
    endfor
    return {}
endfunction

function! s:ProblemIdFromNr(nr) abort
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
            \ 'typescript': 'ts',
            \ 'php': 'php',
            \ 'dart': 'dart',
            \ 'elixir': 'ex',
            \ 'erlang': 'erl',
            \ 'racket': 'rkt',
            \ }

function! s:SolutionFileExt(filetype) abort
    " Unknown languages keep their LeetCode name as the extension.
    return get(s:file_type_to_ext, a:filetype, a:filetype)
endfunction

function! leetcode#ResetSolution(with_latest_submission) abort
    if s:CheckSignIn() == v:false
        return
    endif

    let problem_slug = s:ProblemSlugFromFileName()
    let problem = leetcode#Api('GetProblem', problem_slug)
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
        let submissions = leetcode#Api('GetSubmissions', problem_slug)
        if type(submissions) == v:t_list
            for submission in submissions
                let detail = leetcode#Api('GetSubmission', submission['id'])
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
    call append('$', code)
    silent! normal! ggdd
    let b:leetcode_slug = problem_slug
    call s:ShowDescription(problem)
endfunction

" Show the description of `problem` above the current (solution) window.
function! s:ShowDescription(problem) abort
    let problem = a:problem
    let solution_nr = bufnr('%')
    let problem_desc_file_name = printf('[DESCRIPTION] %s.%s', problem['fid'], problem['slug'])
    if buflisted(problem_desc_file_name)
        " Keep the solution in this window; show the description above it
        " only if it isn't visible already.
        let desc_bufnr = bufnr(problem_desc_file_name)
        call setbufvar(desc_bufnr, 'leetcode_solution_bufnr', solution_nr)
        if bufwinnr(desc_bufnr) == -1
            execute 'leftabove sbuffer ' . desc_bufnr
            execute 'wincmd j'
        endif
        return
    endif

    let lines = s:DescriptionLines(problem)
    execute 'leftabove ' . min([len(lines), max([10, &lines / 2])]) . 'new '
                \ . problem_desc_file_name
    call setline(1, lines)
    call s:SetupDescriptionBuffer()
    let b:leetcode_solution_bufnr = solution_nr

    execute 'wincmd j'
endfunction

function! s:Count(n) abort
    return a:n >= 1000000 ? printf('%.1fM', a:n / 1000000.0)
                \ : a:n >= 1000 ? printf('%.1fK', a:n / 1000.0) : string(a:n)
endfunction

" The problem as a Markdown document: title, facts, description, then the
" hints and similar questions.
function! s:DescriptionLines(problem) abort
    let p = a:problem
    let base = leetcode#BaseUrl()
    let dot = &encoding ==# 'utf-8' ? ' · ' : ' | '
    let facts = ['**' . p['level'] . '**',
                \ printf('%s accepted (%s of %s)', p['ac_rate'], p['total_accepted'],
                \        p['total_submission'])]
    if get(p, 'likes', 0) > 0
        call add(facts, s:Count(p['likes']) . ' likes')
    endif
    let lines = [printf('# %s. %s', p['fid'], p['title']), '', join(facts, dot)]
    if !empty(get(p, 'topics', []))
        call add(lines, 'Topics: ' . join(p['topics'], ', '))
    endif
    call extend(lines, ['', printf('%s/problems/%s/', base, p['slug']), ''])
    call extend(lines, leetcode#html#ToMarkdown(p['content'], base))

    let hints = get(p, 'hints', [])
    if !empty(hints)
        call extend(lines, ['', '## Hints', ''])
        for i in range(len(hints))
            let hint = filter(leetcode#html#ToMarkdown(hints[i], base), 'v:val !=# ""')
            call add(lines, printf('%d. %s', i + 1, join(hint, ' ')))
        endfor
    endif

    let similar = get(p, 'similar', [])
    if !empty(similar)
        call extend(lines, ['', '## Similar Questions', ''])
        for q in similar
            call add(lines, printf('- [%s](%s/problems/%s/)%s', q['title'], base, q['slug'],
                        \ empty(q['level']) ? '' : dot . q['level']))
        endfor
    endif
    return lines
endfunction

function! s:SetupDescriptionBuffer() abort
    setlocal filetype=markdown
    setlocal buftype=nofile bufhidden=hide noswapfile
    setlocal nomodifiable nomodified nospell nonumber norelativenumber
    setlocal wrap linebreak conceallevel=2
    " Hints give the solution away: keep them folded until asked for.
    setlocal foldmethod=manual foldenable
    normal! zE
    let first = search('^## Hints$', 'nw')
    if first > 0
        let last = search('^## Similar Questions$', 'nw')
        execute first . ',' . (last > first ? last - 2 : line('$')) . 'fold'
        execute first . 'foldclose'
    endif
    nnoremap <silent> <buffer> <CR> :call <SID>HandleDescriptionCR()<CR>
endfunction

" <CR> opens a similar question, or the fold under the cursor.
function! s:HandleDescriptionCR() abort
    if foldclosed('.') != -1
        normal! zo
        return
    endif
    let slug = matchstr(getline('.'), '/problems/\zs[^/)]\+\ze/\=)')
    if !empty(slug)
        wincmd j
        call leetcode#OpenProblem(slug)
    endif
endfunction

" Languages whose description is a /* ... */ block.
let s:block_comment_filetypes = ['java', 'c', 'javascript', 'cpp', 'csharp',
            \ 'swift', 'scala', 'kotlin', 'rust', 'typescript', 'php', 'dart']

" Languages whose description is a run of line comments with this prefix.
let s:line_comment_prefixes = {'python': '#', 'python3': '#', 'ruby': '#',
            \ 'elixir': '#', 'golang': '//', 'erlang': '%', 'racket': ';'}

function! s:CommentStart(filetype, title) abort
    if index(s:block_comment_filetypes, a:filetype) >= 0
        return '/* ' . a:title
    elseif has_key(s:line_comment_prefixes, a:filetype)
        return s:line_comment_prefixes[a:filetype] . ' ' . a:title
    else
        return a:title
    endif
endfunction

function! s:CommentLine(filetype, line) abort
    if index(s:block_comment_filetypes, a:filetype) >= 0
        return ' * ' . a:line
    elseif has_key(s:line_comment_prefixes, a:filetype)
        return s:line_comment_prefixes[a:filetype] . ' ' . a:line
    else
        return a:line
    endif
endfunction

function! s:CommentEnd(filetype) abort
    if index(s:block_comment_filetypes, a:filetype) >= 0
        return ' * [End of Description] */'
    elseif has_key(s:line_comment_prefixes, a:filetype)
        return s:line_comment_prefixes[a:filetype] . ' [End of Description]'
    else
        return ''
    endif
endfunction

function! s:GuessFileType() abort
    " Try figuring out the file type from the comment in the first 10
    " lines. If failed, try guessing it from the extension name.
    for line in getline(1, 10)
        let filetype = matchstr(line, '\[filetype:[[:alnum:]]\+\]')
        if filetype !=# ''
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

    if ext ==# 'py'
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

" :LeetCodeTest and :LeetCodeSubmit act on a solution: the current buffer, or
" the one that the description, test input or result window belongs to. Go
" to its window; false (with a message) when there is none.
function! s:GoToSolution() abort
    let nr = get(b:, 'leetcode_solution_bufnr', bufnr('%'))
    if nr != bufnr('%')
        if !bufexists(nr)
            call s:NotASolution()
            return v:false
        endif
        let win = bufwinnr(nr)
        if win > 0
            execute win . 'wincmd w'
        else
            execute 'rightbelow sbuffer ' . nr
        endif
    endif
    if exists('b:leetcode_slug')
        return v:true
    endif
    " A solution file from an earlier session, e.g. 1.two_sum.cpp.
    try
        let slug = s:ProblemSlugFromFileName()
    catch /^leetcode: invalid file name/
        let slug = ''
    endtry
    if empty(slug) || index(values(s:file_type_to_ext), expand('%:e')) < 0
        call s:NotASolution()
        return v:false
    endif
    return v:true
endfunction

function! s:NotASolution() abort
    echohl ErrorMsg
    echomsg 'leetcode.vim: this is not a solution file. Open a problem with '
                \ . ':LeetCodeList or :LeetCodeOpen first.'
    echohl None
endfunction

function! leetcode#TestSolution() abort
    " In the test input window, :LeetCodeTest runs the test.
    if get(b:, 'leetcode_test_input', 0)
        silent wq
        return
    endif
    if s:CheckSignIn() == v:false || !s:GoToSolution()
        return
    endif
    let s:last_solution_nr = bufnr('%')

    let slug = s:ProblemSlugFromFileName()
    let filetype = s:GuessFileType()

    if exists('b:leetcode_problem')
        let problem = b:leetcode_problem
    else
        let problem = leetcode#Api('GetProblem', slug)
        if type(problem) != v:t_dict
            return
        endif
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
    let solution_nr = bufnr('%')
    execute 'rightbelow new ' . tempname()
    setlocal noswapfile
    setlocal nobackup
    setlocal bufhidden=delete
    setlocal nospell
    setlocal nobuflisted

    syn match TestInputComment /\v^#.*/

    let slug = a:problem['slug']

    let header = [printf('# Test input for %s. %s, as on LeetCode: one argument per line.',
                \ a:problem['fid'], a:problem['title']),
                \ '# Save and close this window (:wq, or :LeetCodeTest) to run it; :q! cancels.']
    let test_input = copy(get(s:saved_test_input, slug, a:problem['testcase']))
    " Drop the header saved with an earlier run.
    while !empty(test_input) && test_input[0] =~# '^#'
        call remove(test_input, 0)
    endwhile

    call append('$', header + test_input)

    silent! normal! ggdd
    call cursor(len(header) + 1, 1)
    let b:leetcode_test_input = 1
    let b:leetcode_solution_bufnr = solution_nr
    echo 'Edit the test input, then :wq (or :LeetCodeTest) to run it; :q! cancels.'

    let s:leetcode_problem = a:problem
    let s:leetcode_code = a:code
    let s:leetcode_filetype = a:filetype

    augroup leetcode_test_input
        autocmd! * <buffer>
        autocmd BufUnload <buffer> call s:RunTest()
    augroup END
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

    if test_input ==# ''
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

    if s:backend ==# 'vim'
        call leetcode#api#TestSolutionAsync(args.problem_id, args.title, args.slug,
                    \ args.filetype, args.code, args.test_input,
                    \ function('s:HandleTaskResult', ['test_solution']))
    elseif has('timers')
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
    if s:CheckSignIn() == v:false || !s:GoToSolution()
        return
    endif
    let s:last_solution_nr = bufnr('%')

    let slug = s:ProblemSlugFromFileName()
    let filetype = s:GuessFileType()

    if s:backend ==# 'vim'
        call leetcode#api#SubmitSolutionAsync(slug, filetype, join(getline(1, '$'), "\n"),
                    \ function('s:HandleTaskResult', ['submit_solution']))
    elseif has('timers')
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
    let block = copy(a:block)
    " The judge often ends answers with an empty line.
    while !empty(block) && block[-1] ==# ''
        call remove(block, -1)
    endwhile
    if len(block) > 0
        call add(result, repeat('#', a:level) . ' ' . a:title)
        for line in block
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
    let kind = get(result, 'kind', '')
    let output = ['# ' . result['title'] . (empty(kind) ? '' : ' (' . kind . ')'),
                \ '',
                \ '## State',
                \ '  - ' . result['state'],
                \ '',
                \ '## Runtime',
                \ '  - ' . result['runtime'],
                \ '']
    if !empty(result['runtime_percentile'])
        let message = printf('  - Faster than %s%% submissions',
                    \ result['runtime_percentile'])
        call extend(output, [
                    \ '## Runtime Rank',
                    \ message,
                    \ '',
                    \ ])
    endif

    if !empty(get(result, 'memory', ''))
        call extend(output, ['## Memory', '  - ' . result['memory']
                    \ . (empty(get(result, 'memory_percentile', '')) ? ''
                    \     : printf(', less than %s%% of submissions', result['memory_percentile'])),
                    \ ''])
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
    " Results arrive later: link them to the solution that was run.
    let b:leetcode_solution_bufnr = get(s:, 'last_solution_nr', -1)
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

    let first = search('^### Actual Answer$', 'nw')
    let expected = get(a:result, 'expected_answer', [])
    if first > 0 && !empty(expected)
        let lines = []
        for i in range(len(a:result['answer']))
            if get(expected, i, v:null) isnot# a:result['answer'][i]
                call add(lines, first + 1 + i)
            endif
        endfor
        if !empty(lines)
            call matchaddpos('lcMismatch', lines)
        endif
    endif

    execute saved_winnr . 'wincmd w'
    " Only a submission changes the problem's status, as on the website.
    if get(a:result, 'kind', '') ==# 'submission'
        call s:UpdateSubmitState(a:result)
    endif
endfunction

function! s:CheckRunCodeTask(timer) abort
    if !py3eval('leetcode.task_done')
        let prog = py3eval('leetcode.task_progress')
        echo prog
        return
    endif

    call timer_stop(a:timer)
    call s:HandleTaskResult(py3eval('leetcode.task_name'), py3eval('leetcode.task_output'),
                \ py3eval('leetcode.task_err'))
endfunction

" Show the result of a test run or submission, from either backend.
function! s:HandleTaskResult(task_name, output, error) abort
    echo 'Done'
    if a:error !=# ''
        echom 'error: ' . a:error
    endif
    let task_output = a:output
    if type(task_output) != v:t_dict
        return
    endif
    if a:task_name ==# 'test_solution'
        let task_output['kind'] = 'test run'
        if task_output['state'] ==# 'Finished'
            " The judge says whether the answers are right; older replies
            " don't, so compare them then.
            let correct = get(task_output, 'correct_answer', v:null)
            if type(correct) != v:t_bool && type(correct) != v:t_number
                let correct = task_output['answer'] == task_output['expected_answer']
            endif
            let task_output['state'] = correct ? 'Accepted' : 'Wrong Answer'
        endif
    elseif a:task_name ==# 'submit_solution'
        let task_output['kind'] = 'submission'
        if task_output['state'] ==# 'Finished'
            let task_output['state'] = 'Accepted'
        endif
    endif
    call s:ShowRunResultInPreview(task_output)
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
    endif

    let b:leetcode_problem_slug = a:slug

    let submissions = leetcode#Api('GetSubmissions', a:slug)
    let b:leetcode_submissions = submissions
    if type(submissions) != v:t_list
        return
    endif

    let problem = leetcode#Api('GetProblem', a:slug)
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

    let submission = leetcode#Api('GetSubmission', submission_id)
    if type(submission) != v:t_dict
        return
    endif

    let file_name = printf('%s.%s.%s.%s', 
                \ submission['problem_id'],
                \ s:SlugToFileName(submission['slug']),
                \ submission_id, s:SolutionFileExt(submission['filetype']))

    if bufexists(file_name)
        execute bufnr(file_name) . 'buffer'
        return
    endif

    execute 'rightbelow vnew ' . file_name
    " A past submission to read or start from, not a file to save.
    setlocal buftype=nofile bufhidden=hide noswapfile
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

function! s:UpdateSubmitState(result) abort
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
