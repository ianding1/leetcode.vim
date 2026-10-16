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
  no Python needed. Works in Vim 8.2+ and Neovim. The Python backend stays
  the default for now.

### Python backend
- The bundled copies of requests/urllib3 are gone: they no longer import on
  Python 3.12+ (#81). Install `requests` and `beautifulsoup4` for the Python
  Vim uses; if they are missing, the plugin says so and prints the command.
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
