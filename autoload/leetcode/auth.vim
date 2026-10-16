" vim: sts=4 sw=4 expandtab
"
" Sign-in by pasting the browser's LeetCode cookie, and storage for it.
"
" LeetCode offers no API tokens, and logging in with a password is blocked
" by a CAPTCHA, so the plugin uses the session cookie of a signed-in browser.
" The cookies are kept per site in a JSON file that only the user can read.

" The only cookie the plugin needs and keeps: the CSRF token LeetCode also
" wants is fetched by the plugin itself (see s:RefreshCsrfToken() in api.vim).
let s:wanted = ['LEETCODE_SESSION']

" Accepts what people copy from the browser's developer tools:
"   Cookie: a=b; LEETCODE_SESSION=...; csrftoken=...
"   LEETCODE_SESSION=...; csrftoken=...
"   ...                    (just the value of LEETCODE_SESSION)
" Returns {name: value} with the cookies the plugin needs, {} for nothing.
function! leetcode#auth#ParseCookie(text) abort
    let text = substitute(trim(a:text), '\c^cookie:\s*', '', '')
    if empty(text)
        return {}
    endif
    if text !~# '='
        return {'LEETCODE_SESSION': text}
    endif
    let cookies = {}
    for pair in split(text, ';')
        let m = matchlist(pair, '^\s*\([^=]\{-}\)\s*=\s*\(.\{-}\)\s*$')
        if !empty(m) && index(s:wanted, m[1]) >= 0
            let cookies[m[1]] = trim(m[2], '"')
        endif
    endfor
    return cookies
endfunction

function! leetcode#auth#CookieFile() abort
    if !empty(get(g:, 'leetcode_cookie_file', ''))
        return expand(g:leetcode_cookie_file)
    endif
    if has('nvim')
        let dir = stdpath('data')
    elseif has('win32')
        let dir = expand('$LOCALAPPDATA')
    elseif !empty($XDG_DATA_HOME)
        let dir = $XDG_DATA_HOME
    else
        let dir = expand('~/.local/share')
    endif
    return dir . '/leetcode.vim/cookies.json'
endfunction

function! s:ReadAll() abort
    let file = leetcode#auth#CookieFile()
    if !filereadable(file)
        return {}
    endif
    try
        let data = json_decode(join(readfile(file), "\n"))
    catch
        return {}
    endtry
    return type(data) == v:t_dict ? data : {}
endfunction

" The saved cookies for `host` (e.g. 'leetcode.com'), or {}.
function! leetcode#auth#Load(host) abort
    let cookies = get(s:ReadAll(), a:host, {})
    if type(cookies) != v:t_dict
        return {}
    endif
    let kept = filter(copy(cookies), 'index(s:wanted, v:key) >= 0')
    if kept != cookies
        " Written by an earlier version, with a csrftoken: drop it.
        call leetcode#auth#Save(a:host, kept)
    endif
    return kept
endfunction

" Save the cookies for `host`; {} forgets them.
function! leetcode#auth#Save(host, cookies) abort
    let file = leetcode#auth#CookieFile()
    let data = s:ReadAll()
    if empty(a:cookies)
        if !has_key(data, a:host)
            return
        endif
        call remove(data, a:host)
    else
        let data[a:host] = filter(copy(a:cookies), 'index(s:wanted, v:key) >= 0')
    endif
    let dir = fnamemodify(file, ':h')
    if !isdirectory(dir)
        call mkdir(dir, 'p', 0700)
    endif
    " Restrict the file before the cookies go in.
    if !filereadable(file)
        call writefile([], file)
    endif
    call setfperm(file, 'rw-------')
    call writefile([json_encode(data)], file)
endfunction
