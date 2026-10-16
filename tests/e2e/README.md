# End-to-end tests

These tests run the plugin in a real, headless Vim and Neovim and drive it the
way a user would: `:LeetCodeList`, `<CR>` on a problem, `:LeetCodeTest` then `:wq` on the
test input, `:LeetCodeSubmit`, `s` for submissions. Each scenario's final
state (every buffer's text, echoed output, `:messages`, errors) is checked
from pytest.

The plugin talks to a local HTTP server (`lib/fake_leetcode.py`) instead of
leetcode.com. That server either replays fixtures or proxies to the real site.

```
pytest ──> Vim (+python3) ──HTTP──> fake_leetcode ──(live mode)──> leetcode.com
               │                         │
               └─ plugin under test      └─ logs every request; replays or records
```

## Running

```sh
pip install -r tests/e2e/requirements.txt   # pytest, for the runner's python3
pytest                                      # replay mode, offline
```

Every test runs once per backend and editor (`[python-vim]`, `[vim-nvim]`,
...). Pick with `--lc-backend python|vim` (or `$LEETCODE_E2E_BACKEND`) and
`--lc-editor vim|nvim` (or `$LEETCODE_E2E_EDITOR`); an editor that isn't
installed is skipped. Tests marked `python_only` or `vim_only` exercise one
backend's internals.

Requirements:

- Vim: `+python3`, and a `pythonX.Y` binary matching the Python Vim embeds.
- Neovim: `python3` on PATH (or `$LEETCODE_E2E_NVIM_PYTHON`). The Python host
  runs from a virtualenv of it without site-packages, with `pynvim` added.

On first run the plugin's dependencies (`vim-requirements.txt`) are installed
for each editor's Python into `.e2e-cache/` and passed in through
`PYTHONPATH`. Your own editor setup is not used (`-u NONE`, a temporary
`$HOME`).

### Replay mode (default)

Answers come from `fixtures/legacy/`. These follow the response shapes the
plugin was written against (2019–2020), so replay mode tests the plugin's
own logic: parsing, rendering, navigation, the async run/submit worker. It
says nothing about whether leetcode.com still answers that way. Live mode
does that.

### Live mode

```sh
export LEETCODE_SESSION='...'     # the cookie of a browser signed in to leetcode.com
pytest --lc-mode=live                                  # read-only checks
pytest --lc-mode=live --lc-allow-submit                # also submits Two Sum
pytest --lc-mode=live --lc-record=tests/e2e/fixtures/recorded
```

- Tests that create a real submission (`@pytest.mark.submits`) only run with
  `--lc-allow-submit`. `:LeetCodeTest` runs are not submissions and do run.
- `--lc-record DIR` saves every live response as a fixture. Replay them with
  `pytest --lc-fixtures DIR`. Recorded fixtures can contain account data
  (username, submission code), so `fixtures/recorded/` is git-ignored.
- `--lc-upstream https://leetcode.cn` targets LeetCode China.

`test_00_api.py` calls each Python API function on its own (progress,
problem list, topics, problem detail, submissions…). In live mode it shows
which endpoints still work, even when a UI command fails on an earlier call.

## Known failures

When a test pins down a confirmed bug that isn't fixed yet, mark it
`xfail(strict=True)` and give the bug as the reason. It shows as `XFAIL`
while the bug exists, then `XPASS` (failing the run) once it is fixed, so the
marker gets removed. There are none at the moment.

## Writing a test

```python
def test_something(scenario, lc):
    s = scenario().signed_in(lc.cookies)   # saved cookie, as after an earlier sign-in
    s.step('LeetCodeList')                 # any Ex command; exceptions are recorded
    s.goto(r'| Two Sum ')                  # move the cursor to a line
    s.press(r'\<CR>')                      # normal-mode keys, buffer mappings apply
    s.wait_for_buffer(r'leetcode:///result', 30000)
    s.capture('name', 'any vim expression')
    r = s.run()
    r.assert_ok()                          # no step raised
    assert 'Accepted' in r.text(r'^leetcode:///result$')
```

Other ways to sign in: `s.type_ahead(r'LEETCODE_SESSION=...\<CR>')` answers
the sign-in prompt (any prompt needs its keys queued like this, or headless
Vim exits and Neovim hangs), and `s.browser_has(lc.cookies)` fakes the browser
cookie store for `g:leetcode_browser = 'chrome'`. `lc.server.valid_sessions`
limits which sessions the fake server accepts.

To call the API directly, use `leetcode#Api('GetProblem', 'two-sum')` after
`call leetcode#SignIn(0)`; it goes to whichever backend is selected.

In replay mode, `lc.server.override(route, response)` replaces a fixture for
one test (for example a 403, or a different judge result), and
`lc.server.requests_to(route)` returns what the plugin sent. Route names and
the fixture file format are documented in `lib/fake_leetcode.py`. When a test
fails, the message includes the generated Vim script path. Run it by hand
with
`PYTHONPATH=.e2e-cache/pydeps-pyX.Y vim -N -u NONE -S <path>` to reproduce.
