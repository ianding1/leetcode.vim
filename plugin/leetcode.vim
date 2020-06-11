" vim: sts=4 sw=4 expandtab

if !exists('g:leetcode_china')
    let g:leetcode_china = 0
endif

if !exists('g:leetcode_browser')
    let g:leetcode_browser = 'disabled'
endif

if !exists('g:leetcode_categories')
    let g:leetcode_categories = ['algorithms']
endif

if !exists('g:leetcode_solution_filetype')
    let g:leetcode_solution_filetype = 'cpp'
endif

if !exists('g:leetcode_debug')
    let g:leetcode_debug = 0
endif

if !exists('g:leetcode_hide_paid_only')
    let g:leetcode_hide_paid_only = 0
endif

if !exists('g:leetcode_hide_topics')
    let g:leetcode_hide_topics = 0
endif

if !exists('g:leetcode_hide_companies')
    let g:leetcode_hide_companies = 0
endif

if !exists('g:leetcode_problemset')
    let g:leetcode_problemset = 'all'
endif

command! -nargs=0 LeetCodeList call leetcode#ListProblems('redraw')
command! -nargs=0 LeetCodeReset call leetcode#ResetSolution(0)
command! -nargs=0 LeetCodeTest call leetcode#TestSolution()
command! -nargs=0 LeetCodeSubmit call leetcode#SubmitSolution()
command! -nargs=0 LeetCodeSignIn call leetcode#SignIn(1)
