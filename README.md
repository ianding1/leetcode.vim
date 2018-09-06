# leetcode.vim

Solve LeetCode problems in Vim!

This Vim plugin is inspired by [skygragon/leetcode-cli](https://github.com/skygragon/leetcode-cli).

## Installation

1. Vim with Python3 support is **required**. If you are using Neovim, you probably need to install the Neovim Python API:
```
pip3 install neovim --user
```
2. This plugin requires **requests** and **beautifulsoup4**, which can be installed by running:
```
pip3 install requests beautifulsoup4 --user
```
3. To install the plugin, you only need to place the following line in your vimrc if you are using vim-plugged (or similar code for other plugin managers):
```
Plug 'iandingx/leetcode.vim'
```

## Quick Start

1. Run `:LeetCodeList` to browse the problems (you may need to enter username and password to sign in, see Customization if you want to skip this step).
2. Press Enter on the line of a problem to open a file to write your solution.
3. Run `:LeetCodeTest` in your solution file to test the solution with a simple test case (you may need to press `ctrl-w z` to close the result window).
4. Run `:LeetCodeSubmit` in your solution file to submit it to LeetCode and receive the result (you may need to press `ctrl-w z` to close the result window).
5. To manually sign in or switch an account, run `:LeetCodeSignIn`.

Or you can simply put the following lines in your vimrc to bind these commands to shortcuts:

```
nnoremap <leader>ll :LeetCodeList<cr>
nnoremap <leader>lt :LeetCodeTest<cr>
nnoremap <leader>ls :LeetCodeSubmit<cr>
nnoremap <leader>li :LeetCodeSignIn<cr>
```

## Customization

### g:leetcode\_solution\_filetype

The language that you use to solve the problem. It can be one of the following values: `'cpp'`, `'java'`, `'python'`, `'python3'`, `'csharp'`, `'javascript'`, `'ruby'`, `'swift'`, `'golang'`, `'scala'`, `'kotlin'`.

Default value is `'cpp'`.

### g:leetcode\_categories

The problem categories that you want to browse. It can be a list of the following values: `'algorithms'`, `'database'`, `'shell'`.

Default value is `['algorithms']`.

### g:leetcode\_username

If you want to automatically login to LeetCode, put your LeetCode username here.

Default value is `''`.

### g:leetcode\_password

If you want to automatically login to LeetCode, put your LeetCode password here.

WARNING: the password is stored in disk in plain text. So make sure it won't be leaked.

Default value is `''`.

## FAQ

### [PLEASE READ THIS] Why can't I test the problem/submit the problem/list the problems?

Once you sign in on your browser in LeetCode website, the LeetCode session in Vim get expired immediatelly. Then you need to sign in again in Vim before doing other things.
