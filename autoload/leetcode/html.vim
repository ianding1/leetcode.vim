" vim: sts=4 sw=4 expandtab
scriptencoding utf-8
"
" Turn the HTML of a problem description into plain text, without Python.
" LeetCode descriptions use a small set of tags (p, pre, code, strong, em,
" ul/ol/li, sup, sub, img, br), so a few substitutions cover them.

let s:entities = {
            \ 'nbsp': ' ', 'lt': '<', 'gt': '>', 'amp': '&', 'quot': '"',
            \ 'apos': "'", 'le': '≤', 'ge': '≥', 'ne': '≠', 'times': '×',
            \ 'minus': '−', 'hellip': '…', 'mdash': '—', 'ndash': '–',
            \ 'rarr': '→', 'larr': '←', 'lsquo': '‘', 'rsquo': '’',
            \ 'ldquo': '“', 'rdquo': '”',
            \ }

function! s:Entity(name) abort
    if a:name =~? '^#x\x\+$'
        return nr2char(str2nr(a:name[2:], 16))
    elseif a:name =~# '^#\d\+$'
        return nr2char(str2nr(a:name[1:]))
    endif
    return get(s:entities, a:name, '&' . a:name . ';')
endfunction

" The description as text, with newlines where the HTML has blocks.
function! leetcode#html#ToText(html) abort
    let s = substitute(a:html, '\r\n\=', '\n', 'g')
    let s = substitute(s, '\c<\(script\|style\)\>\_.\{-}</\1>', '', 'g')
    let s = substitute(s, '\c<br\s*/\=>', '\n', 'g')
    " 10<sup>4</sup> would otherwise read as 104.
    let s = substitute(s, '\c<sup>\(\_.\{-}\)</sup>', '^\1', 'g')
    let s = substitute(s, '\c<sub>\(\_.\{-}\)</sub>', '_\1', 'g')
    let s = substitute(s, '\c<li\>[^>]*>', '\n- ', 'g')
    let s = substitute(s, '\c</li>', '\n', 'g')
    let s = substitute(s, '\c<img\>[^>]*\<alt="\([^"]*\)"[^>]*>', '[image: \1]', 'g')
    " Block boundaries get a line of their own, marked with \x01.
    let s = substitute(s, '\c</\=\(p\|div\|pre\|ul\|ol\|h[1-6]\|table\|tr\|blockquote\)\>[^>]*>',
                \ "\n\x01\n", 'g')
    let s = substitute(s, '<[^>]*>', '', 'g')
    " Decode entities last, so a decoded '<' is never taken for a tag.
    let s = substitute(s, '&\(#\=\w\+\);', '\=s:Entity(submatch(1))', 'g')
    return substitute(s, nr2char(160), ' ', 'g')
endfunction

" The description as lines for the description window: one empty line
" between blocks (paragraphs, examples, lists), none inside an example or
" between list items. autoload/leetcode.py does the same.
function! leetcode#html#ToLines(html) abort
    let result = []
    let gap = 0
    for line in split(leetcode#html#ToText(a:html), "\n")
        if line ==# "\x01"
            let gap = !empty(result)
        elseif line =~# '\S'
            if gap
                call add(result, '')
            endif
            call add(result, substitute(line, '\s\+$', '', ''))
            let gap = 0
        endif
    endfor
    return empty(result) ? result : add(result, '')
endfunction
