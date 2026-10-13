" Helpers sourced into the headless Vim that runs one e2e scenario.
" vim: sts=4 sw=4 expandtab

let g:e2e_steps = []
let g:e2e_vars = {}

" Run one Ex command and record whether it raised.
function! E2EStep(cmd) abort
    let rec = {'cmd': a:cmd, 'error': '', 'output': ''}
    let output = ''
    " :redir also captures :echo output, which :messages does not keep.
    " (Not execute(): prompts such as inputlist() return 0 inside it.)
    redir => output
    try
        execute a:cmd
    catch
        let rec.error = v:exception . ' @ ' . v:throwpoint
    finally
        redir END
    endtry
    let rec.output = output
    call add(g:e2e_steps, rec)
endfunction

" Let timers and the plugin's worker thread run until `expr` is true.
function! E2EWaitFor(expr, timeout_ms) abort
    let rec = {'cmd': 'wait for ' . a:expr, 'error': ''}
    let waited = 0
    while 1
        try
            if eval(a:expr)
                break
            endif
        catch
        endtry
        if waited >= a:timeout_ms
            let rec.error = 'timed out after ' . a:timeout_ms . 'ms'
            break
        endif
        sleep 50m
        let waited += 50
    endwhile
    call add(g:e2e_steps, rec)
endfunction

" Store the value of `expr` under `name` in the result.
function! E2ECapture(name, expr) abort
    try
        let g:e2e_vars[a:name] = eval(a:expr)
    catch
        let g:e2e_vars[a:name] = {'capture_error': v:exception}
    endtry
endfunction

function! E2EBufferLoaded(pattern) abort
    for b in range(1, bufnr('$'))
        if bufloaded(b) && bufname(b) =~# a:pattern
            return 1
        endif
    endfor
    return 0
endfunction

" Write everything a test may want to assert on, then quit.
function! E2EFinish() abort
    let buffers = {}
    for b in range(1, bufnr('$'))
        if bufexists(b) && bufloaded(b)
            let buffers[bufname(b)] = getbufline(b, 1, '$')
        endif
    endfor
    let result = {
                \ 'steps': g:e2e_steps,
                \ 'vars': g:e2e_vars,
                \ 'buffers': buffers,
                \ 'current_buffer': bufname('%'),
                \ 'messages': split(execute('messages'), "\n"),
                \ }
    call writefile([json_encode(result)], g:e2e_out)
    qa!
endfunction
