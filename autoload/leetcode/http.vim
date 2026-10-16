" vim: sts=4 sw=4 expandtab
"
" HTTP requests through curl, without Python. Works in Vim 8.2+ and Neovim.
"
" A request is a dict:
"   url       (required)
"   method    'GET' by default
"   headers   {name: value}
"   cookies   {name: value}
"   body      string sent as is
"   json      any value; sent JSON-encoded as application/json
"   timeout   seconds, 30 by default
"
" A response is a dict:
"   status    HTTP status code, 0 if no response was received
"   headers   {lowercased name: value} of the final response
"   body      string
"   error     '' on success, otherwise why curl failed
"
" Everything, including cookies, is passed to curl as a config file on stdin
" (curl -K -), so secrets never show up in the process list.

function! s:Quote(value) abort
    " A double-quoted string for a curl config file.
    let value = escape(a:value, '"\')
    let value = substitute(value, "\n", '\\n', 'g')
    let value = substitute(value, "\r", '\\r', 'g')
    let value = substitute(value, "\t", '\\t', 'g')
    return '"' . value . '"'
endfunction

function! s:Prepare(opts) abort
    let req = {'body_file': tempname(), 'header_file': tempname(), 'data_file': ''}
    let lines = [
                \ 'url = ' . s:Quote(a:opts.url),
                \ 'request = ' . s:Quote(get(a:opts, 'method', 'GET')),
                \ 'max-time = ' . get(a:opts, 'timeout', 30),
                \ 'silent',
                \ 'show-error',
                \ 'output = ' . s:Quote(req.body_file),
                \ 'dump-header = ' . s:Quote(req.header_file),
                \ 'write-out = "%{http_code}"',
                \ ]

    let headers = copy(get(a:opts, 'headers', {}))
    let body = get(a:opts, 'body', v:null)
    if has_key(a:opts, 'json')
        let body = json_encode(a:opts.json)
        let headers['Content-Type'] = 'application/json'
    endif
    if type(body) == v:t_string
        let req.data_file = tempname()
        call writefile(split(body, "\n", 1), req.data_file, 'b')
        call add(lines, 'data-binary = ' . s:Quote('@' . req.data_file))
    endif

    for [name, value] in items(headers)
        call add(lines, 'header = ' . s:Quote(name . ': ' . value))
    endfor

    let cookies = get(a:opts, 'cookies', {})
    if !empty(cookies)
        let pairs = map(items(cookies), 'v:val[0] . "=" . v:val[1]')
        call add(lines, 'cookie = ' . s:Quote(join(pairs, '; ')))
    endif

    let req.config = join(lines, "\n") . "\n"
    return req
endfunction

function! s:ParseHeaders(lines) abort
    let headers = {}
    for line in a:lines
        let line = substitute(line, '\r$', '', '')
        if line =~# '^HTTP/'
            " A new response (after a redirect or 100 Continue) starts over.
            let headers = {}
        elseif line =~# '^[^:]\+:'
            let name = tolower(matchstr(line, '^[^:]\+'))
            let value = trim(matchstr(line, '^[^:]\+:\zs.*'))
            " Several Set-Cookie headers are kept, one per line.
            let headers[name] = name ==# 'set-cookie' && has_key(headers, name)
                        \ ? headers[name] . "\n" . value : value
        endif
    endfor
    return headers
endfunction

function! s:Finish(req, exit_code, stdout, stderr) abort
    let res = {'status': 0, 'headers': {}, 'body': '', 'error': ''}
    if a:exit_code != 0
        let res.error = printf('curl failed (exit %d): %s', a:exit_code,
                    \ trim(empty(a:stderr) ? a:stdout : a:stderr))
    else
        let res.status = str2nr(trim(a:stdout))
        if filereadable(a:req.body_file)
            let res.body = join(readfile(a:req.body_file, 'b'), "\n")
        endif
        if filereadable(a:req.header_file)
            let res.headers = s:ParseHeaders(readfile(a:req.header_file))
        endif
    endif
    for file in [a:req.body_file, a:req.header_file, a:req.data_file]
        if !empty(file)
            call delete(file)
        endif
    endfor
    return res
endfunction

function! s:NoCurl() abort
    return {'status': 0, 'headers': {}, 'body': '',
                \ 'error': 'curl is not installed or not in $PATH'}
endfunction

" Send a request and wait for the response.
function! leetcode#http#Request(opts) abort
    if !executable('curl')
        return s:NoCurl()
    endif
    let req = s:Prepare(a:opts)
    let stdout = system('curl -K -', req.config)
    " system() mixes stderr into stdout; on success curl only prints the code.
    return s:Finish(req, v:shell_error, stdout, '')
endfunction

" Send a request in the background; call callback(response) when it is done.
function! leetcode#http#RequestAsync(opts, callback) abort
    if !executable('curl')
        call a:callback(s:NoCurl())
        return
    endif
    let req = s:Prepare(a:opts)
    let req.callback = a:callback
    let req.stdout = ''
    let req.stderr = ''
    if has('nvim')
        call s:StartNvim(req)
    else
        call s:StartVim(req)
    endif
endfunction

" Decode a response body as JSON; v:null if it isn't JSON.
function! leetcode#http#Json(res) abort
    try
        return json_decode(a:res.body)
    catch
        return v:null
    endtry
endfunction

" ---- Neovim ------------------------------------------------------------------

function! s:NvimOutput(req, key, job, data, event) abort
    let a:req[a:key] = join(a:data, "\n")
endfunction

function! s:NvimExit(req, job, code, event) abort
    call a:req.callback(s:Finish(a:req, a:code, a:req.stdout, a:req.stderr))
endfunction

function! s:StartNvim(req) abort
    let job = jobstart(['curl', '-K', '-'], {
                \ 'stdout_buffered': v:true,
                \ 'stderr_buffered': v:true,
                \ 'on_stdout': function('s:NvimOutput', [a:req, 'stdout']),
                \ 'on_stderr': function('s:NvimOutput', [a:req, 'stderr']),
                \ 'on_exit': function('s:NvimExit', [a:req]),
                \ })
    call chansend(job, a:req.config)
    call chanclose(job, 'stdin')
endfunction

" ---- Vim ---------------------------------------------------------------------
"
" exit_cb can run before the last output has been read, and close_cb before
" the process has exited. Finish once both have happened.

function! s:VimOutput(req, key, channel, msg) abort
    let a:req[a:key] .= a:msg
endfunction

function! s:VimDone(req) abort
    let a:req.pending -= 1
    if a:req.pending == 0
        call a:req.callback(s:Finish(a:req, a:req.exit_code, a:req.stdout, a:req.stderr))
    endif
endfunction

function! s:VimClose(req, channel) abort
    call s:VimDone(a:req)
endfunction

function! s:VimExit(req, job, code) abort
    let a:req.exit_code = a:code
    call s:VimDone(a:req)
endfunction

function! s:StartVim(req) abort
    let a:req.pending = 2
    let a:req.exit_code = -1
    let job = job_start(['curl', '-K', '-'], {
                \ 'in_io': 'pipe',
                \ 'out_mode': 'raw',
                \ 'err_mode': 'raw',
                \ 'out_cb': function('s:VimOutput', [a:req, 'stdout']),
                \ 'err_cb': function('s:VimOutput', [a:req, 'stderr']),
                \ 'close_cb': function('s:VimClose', [a:req]),
                \ 'exit_cb': function('s:VimExit', [a:req]),
                \ })
    let channel = job_getchannel(job)
    call ch_sendraw(channel, a:req.config)
    call ch_close_in(channel)
endfunction
