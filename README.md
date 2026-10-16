# leetcode.vim

[![asciicast][thumbnail]][asciicast]

Solve LeetCode problems in Vim!

This Vim plugin is inspired by [skygragon/leetcode-cli][leetcode-cli].

**Signing in:** LeetCode has no API tokens and its login page uses a CAPTCHA,
so leetcode.vim signs in with the session cookie of a browser where you are
signed in. The first time it needs one, it asks you to paste the `Cookie`
header of any leetcode.com request (browser developer tools → Network). It
keeps only the `LEETCODE_SESSION` and `csrftoken` cookies, in a file only you
can read, and asks again when the session expires. See `:help
leetcode-sign-in`.

## Installation

By default leetcode.vim needs only **curl** (Vim 8.2+ or Neovim, no Python).
Install the plugin with your plugin manager and you are done.

**With the Python backend** (`let g:leetcode_backend = 'python'`, the default
before 2026/10, and still the one used when `g:leetcode_browser` is
`'chrome'` or `'firefox'`):

1. Vim with `+python3` feature is **required**. Neovim needs the **pynvim**
package (for the Python in `g:python3_host_prog`, or `python3`), and the
packages below go to that same Python:
```sh
pip3 install pynvim --user
```
2. Install **requests** for the Python that Vim uses.
This is not always the `python3` on your `PATH`: check with
`:py3 import sys; print(sys.version)`, then use the matching `pythonX.Y`:
```sh
python3 -m pip install --user requests
```
If they are missing, the plugin says so and prints the command to run.
3. Only if you set `g:leetcode_browser` to `'chrome'` or `'firefox'` to read
the session cookie from the browser: install **keyring** and
**browser-cookie3**:
```sh
pip3 install keyring browser-cookie3 --user
```
4. Install the plugin:
```vim
Plug 'ianding1/leetcode.vim'
```

## Quick Start

- `:LeetCodeList`: browse the problems.
- `:LeetCodeTest`: run the code with the default test case.
- `:LeetCodeSubmit`: submit the code.
- `:LeetCodeSignIn`: sign in, or replace the saved cookie.
- `:LeetCodeSignOut`: sign out and forget the saved cookie.

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

When non-zero, use LeetCode China (leetcode.cn) accounts instead.

Default value is `0`.

### `g:leetcode_solution_filetype`

The preferred programming language.

Values: `'cpp'`, `'java'`, `'python'`, `'python3'`, `'csharp'`, `'javascript'`,
`'ruby'`, `'swift'`, `'golang'`, `'scala'`, `'kotlin'`, ``'rust'``.

Default value is `'cpp'`.

### `g:leetcode_browser`

Where the session cookie comes from: `'paste'` asks for it (see above);
`'chrome'` or `'firefox'` read it from the browser's cookie store (needs the
`keyring` and `browser-cookie3` Python packages); `'env'` reads
`$LEETCODE_SESSION` and `$LEETCODE_CSRFTOKEN`.

Values: `'paste'`, `'chrome'`, `'firefox'`, `'env'`

Default value is `'paste'`.

### `g:leetcode_backend`

`'vim'` (default) talks to LeetCode with Vim script and `curl`, with no
Python at all; `'python'` goes through Python (`requests`).
Reading cookies from a browser's store (`g:leetcode_browser` `'chrome'` or
`'firefox'`) needs the Python backend, which is then the default.

### `g:leetcode_base_url`

The LeetCode site to use, e.g. `'https://leetcode.cn'`. Overrides
`g:leetcode_china` when set.

### `g:leetcode_hide_paid_only`

Hide the paid only problems on the list.

Default value is `0`.

### `g:leetcode_hide_topics`

Hide the topics section.

Default value is `0`

### `g:leetcode_hide_companies`

Hide the companies section.

Default value is `0`

### `g:leetcode_problemset`

Set the problemset to get from leetcode. 

Default value is `all`

## Updates

- 2026/10: Revival release (see [CHANGELOG.md](CHANGELOG.md)):
  + Sign in by pasting the browser cookie; no browser-cookie3/keyring needed
  + No Python needed: the default backend uses Vim script and curl
    (`g:leetcode_backend = 'python'` keeps the old one)
  + Works on Python 3.12+; clear message when Python packages are missing
  + Neovim tested alongside Vim; many crash fixes; end-to-end tests and CI
- 2019/12/20: Fix the login issue caused by reCAPTCHA.
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

### I got some errors like "ModuleNotFoundError: No module named 'keyring.util.escape'"

This solution worked for me:
```shell
pip3 install --upgrade keyrings.alt
```

[thumbnail]: https://asciinema.org/a/200004.png
[asciicast]: https://asciinema.org/a/200004
[leetcode-cli]: https://github.com/skygragon/leetcode-cli
[#5]: https://github.com/ianding1/leetcode.vim/issues/5
