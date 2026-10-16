# Changelog

## Unreleased (2026 revival)

### Signing in
- New default `g:leetcode_browser = 'paste'`: the plugin asks for the `Cookie`
  header of a signed-in browser (hidden input), checks it with LeetCode, and
  keeps `LEETCODE_SESSION` and `csrftoken` in a file only you can read
  (`g:leetcode_cookie_file`). It reuses the saved session and asks again when
  it expires. `:LeetCodeSignIn` replaces it, new `:LeetCodeSignOut` forgets it.
- `g:leetcode_browser = 'env'` reads `$LEETCODE_SESSION` and
  `$LEETCODE_CSRFTOKEN`.
- Browser sign-in now also loads `csrftoken`, and drops expired cached
  cookies. A rejected cookie no longer leaves the plugin looking signed in.

### Python-free backend
- `g:leetcode_backend = 'vim'` talks to LeetCode with Vim script and `curl`;
  no Python needed. Works in Vim 8.2+ and Neovim. It is the new default;
  `let g:leetcode_backend = 'python'` keeps the Python backend, which is also
  still used when `g:leetcode_browser` is `'chrome'` or `'firefox'` (reading
  a browser's cookie store needs Python).

### Python backend
- The bundled copies of requests/urllib3 are gone: they no longer import on
  Python 3.12+ (#81). Install `requests` for the Python
  Vim uses; if it is missing, the plugin says so and prints the command.
- Requests send a browser User-Agent (#77, #83).

### Today's leetcode.com (checked live, both backends)
- Topics and companies come from GraphQL: `/problemset/all/` now answers 403
  to scripts, so scraping it left `:LeetCodeList` without topics.
- Past submissions are read with the `submissionDetails` GraphQL query
  instead of being scraped from their page, which no longer holds the data.
- Company problem lists work again: LeetCode dropped the
  `frequencyTimePeriod` field the query asked for.
- The problem list and submission list use the trailing-slash URLs. Without
  it LeetCode redirects, and the Vim script backend got an empty answer.

### Interface
- The problem list starts with the problems: topics and companies are
  folds, closed by default, and the cursor is on the first problem. Keys,
  sort order and legend fit in three lines.
- `:LeetCodeOpen {number|slug}` opens a problem from anywhere, with
  completion; `f`/`F` filter the list by title or number.
- Test runs say Accepted or Wrong Answer, and highlight the answer lines
  that differ; results show memory use and rank. Only submissions change a
  problem's status (a failed test run used to mark a solved one attempted).
- ✓/~ status marks, colors that follow the colorscheme and can be
  overridden (`:help leetcode-highlights`), and long titles cut with "…".
- The description is a Markdown buffer instead of a comment block: title,
  difficulty, acceptance, likes and topics, examples as code blocks, inline
  code and emphasis kept, hints folded, and similar questions that `<CR>`
  opens (`:help leetcode-description`).
- The Python backend no longer needs beautifulsoup4.
- Solutions are saved in `g:leetcode_solution_dir` (default `~/leetcode`)
  as soon as a problem is opened, instead of being left unsaved in whatever
  directory Vim was in. Opening a problem whose file exists keeps the file
  as it is: it used to replace your code with the template or your last
  submission. Past submissions open as scratch buffers.
- The test input window says how to run the test (`:wq`, or `:LeetCodeTest`
  again in it, which now runs it). `:LeetCodeTest` and `:LeetCodeSubmit`
  work from the description, test input and result windows too: they used
  to take the problem from that window's name and fail. Failed requests
  say the HTTP status.

### Fixes
- `:LeetCodeList` no longer fails with E684 when topics can't be loaded (#78).
- Submissions are no longer shown as test runs when the judge's reply lacks
  `judge_type` (#60).
- Test runs and submissions: no stale results from the previous run, no
  endless polling on unexpected judge states (gives up after 120s), and the
  judge's own error messages instead of KeyError/TypeError tracebacks.
- `t` (time period) in company lists works again (it failed with E117).
- `:LeetCodeReset` on an open problem no longer replaces the code window with
  the description (or fails with E37).
- `:LeetCodeTest` on a problem that can't be fetched no longer fails with E909.
- Opening problems or submissions in other languages no longer fails with
  E716; TypeScript (#63), PHP, Dart, Elixir, Erlang and Racket are supported.
- Runtime rank shows when viewing a past submission, formatted the same in
  Vim and Neovim.
- Problem descriptions keep exponents (`10^4`, not `104`) with the Vim script
  backend.

### Other
- `g:leetcode_china` uses leetcode.cn (leetcode-cn.com moved) (#71);
  `g:leetcode_base_url` selects any site.
- End-to-end tests run the plugin in headless Vim and Neovim against a fake
  LeetCode server, for both backends (`tests/e2e`), plus CI on GitHub
  Actions with vint and flake8.
