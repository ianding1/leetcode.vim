if !exists('g:leetcode_username')
    let g:leetcode_username = ''
endif

if !exists('g:leetcode_password')
    let g:leetcode_password = ''
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

command! -nargs=0 LeetCodeList call leetcode#ListProblems()
command! -nargs=0 LeetCodeReset call leetcode#ResetSolution(0)
command! -nargs=0 LeetCodeTest call leetcode#TestSolution()
command! -nargs=0 LeetCodeSubmit call leetcode#SubmitSolution()
command! -nargs=0 LeetCodeSignIn call leetcode#SignIn(1)
