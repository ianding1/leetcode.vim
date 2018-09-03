if !exists('g:leetcode_username')
    let g:leetcode_username = 0
endif

if !exists('g:leetcode_password')
    let g:leetcode_password = 0
endif

if !exists('g:leetcode_categories')
    let g:leetcode_categories = ['algorithms']
endif

if !exists('g:leetcode_solution_filetype')
    let g:leetcode_solution_filetype = 'cpp'
endif

command! -nargs=0 LeetCodeList call leetcode#ListProblems()
command! -nargs=0 LeetCodeReset call leetcode#ResetProblem()
command! -nargs=0 LeetCodeTest call leetcode#TestProblem()
command! -nargs=0 LeetCodeSubmit call leetcode#SubmitProblem()
command! -nargs=0 LeetCodeSignIn call leetcode#SignIn(1)
