# leetcode.vim

[![asciicast][thumbnail]][asciicast]

Solve LeetCode problems in Vim!

This Vim plugin is inspired by [skygragon/leetcode-cli][leetcode-cli].

**Important Update! Please setup keyring for password safety:**

1. Install keyring with `pip3 install keyring --user`
2. Remove `g:leetcode_password` from your configuration.
3. The first time you sign in, **leetcode.vim** will prompt for the password
and store it in keyring.

## Installation

1. Vim with `+python3` feature is **required**. Install the **pynvim** package
for Neovim:
```sh
pip3 install pynvim --user
```
2. Install **keyring**:
```sh
pip3 install keyring --user
```
3. Install the plugin:
```vim
Plug 'ianding1/leetcode.vim'
```

## Quick Start

- `:LeetCodeList`: browse the problems.
- `:LeetCodeTest`: run the code with the default test case.
- `:LeetCodeSubmit`: submit the code.
- `:LeetCodeSignIn`: manually sign in.

## Key mappings

**leetcode.vim** doesn't bind any key mappings by default. Put the following
lines to your **.vimrc** to set up the key mappings.

```vim
nnoremap <leader>ll :LeetCodeList<cr>
nnoremap <leader>lt :LeetCodeTest<cr>
nnoremap <leader>ls :LeetCodeSubmit<cr>
nnoremap <leader>li :LeetCodeSignIn<cr>
```

## Customization

### `g:leetcode_china`

When non-zero, use LeetCode China accounts instead.

Default value is `0`.

### `g:leetcode_solution_filetype`

The preferred programming language.

Values: `'cpp'`, `'java'`, `'python'`, `'python3'`, `'csharp'`, `'javascript'`,
`'ruby'`, `'swift'`, `'golang'`, `'scala'`, `'kotlin'`, ``'rust'``.

Default value is `'cpp'`.

### `g:leetcode_username`

Set to the LeetCode username or email for auto login.

Default value is `''`.

### `g:leetcode_password`

**Deprecated in favor of keyring.** Set to the LeetCode password for auto login.

If you have installed keyring, then just leave this option blank.
**leetcode.vim** will prompt for the password the first time you sign in, and
store the password in keyring.

**WARNING: the password is stored in plain text.**

Default value is `''`.

## Updates

- 2019/08/01: Support custom test input
- 2019/07/28: Support showing frequencies and sorting by columns
- 2019/07/27:
  + Support LeetCode China accounts
  + Support refreshing
- 2019/07/23: Support topics and companies

## FAQ

### I use Ubuntu and get errors when signing in. How can I fix it?

Ubuntu users might see the error message below when signing in.
```text
    raise InitError("Failed to unlock the collection!")
keyring.errors.InitError: Failed to unlock the collection!
```

It's caused by the misconfiguration of python-keyring. One way to fix it is to create a file `~/.local/share/python_keyring/keyringrc.cfg` with the following content:

```ini
[backend]
default-keyring=keyring.backends.Gnome.Keyring
```

### Why can't I test the problem/submit the problem/list the problems?

~~Once you sign in on your browser in LeetCode website, the LeetCode session in
Vim get expired immediatelly. Then you need to sign in again in Vim before
doing other things.~~ (No longer having this problem)

### Why can't I test and submit solutions?

According to issue [#5][#5], **if the email address is not active, then you can
only login and download problems, but cannot test and submit any code.**

[thumbnail]: https://asciinema.org/a/200004.png
[asciicast]: https://asciinema.org/a/200004
[leetcode-cli]: https://github.com/skygragon/leetcode-cli
[#5]: https://github.com/ianding1/leetcode.vim/issues/5
