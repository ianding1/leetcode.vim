" vim: sts=4 sw=4 expandtab
scriptencoding utf-8
"
" Turn the HTML of a problem description into Markdown, without Python.
" LeetCode descriptions use a small set of tags (p, pre, code, strong, em,
" ul/ol/li, sup, sub, img, a, br), so a few substitutions cover them.

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

" Entities decoded; done last, so a decoded '<' is never taken for a tag.
function! s:Decode(text) abort
    let s = substitute(a:text, '&\(#\=\w\+\);', '\=s:Entity(submatch(1))', 'g')
    return substitute(s, nr2char(160), ' ', 'g')
endfunction

" The text of an HTML fragment, for code: tags dropped, entities decoded.
function! s:PlainText(html) abort
    let s = substitute(a:html, '\c<br\s*/\=>', '\n', 'g')
    " 10<sup>4</sup> would otherwise read as 104.
    let s = substitute(s, '\c<sup>\(\_.\{-}\)</sup>', '^\1', 'g')
    let s = substitute(s, '\c<sub>\(\_.\{-}\)</sub>', '_\1', 'g')
    return s:Decode(substitute(s, '<[^>]*>', '', 'g'))
endfunction

" Code blocks and inline code are set aside while the rest is converted, so
" their text stays as it is: a block becomes a line \x02N\x02 of its own, an
" inline span \x03N\x03.
function! s:Keep(kind, html) abort
    call add(s:kept, s:PlainText(a:html))
    let n = len(s:kept) - 1
    return a:kind ==# 'pre' ? "\n\x01\n\x02" . n . "\x02\n\x01\n" : "\x03" . n . "\x03"
endfunction

function! s:InlineCode(n) abort
    let code = substitute(s:kept[a:n], '\n', ' ', 'g')
    return code =~# '`' ? '`` ' . code . ' ``' : '`' . code . '`'
endfunction

" **text**, keeping the spaces LeetCode puts inside the tag outside the marks.
function! s:Emphasis(mark, lead, text, trail) abort
    return a:lead . (a:text =~# '\S' ? a:mark . a:text . a:mark : a:text) . a:trail
endfunction

function! s:Url(url, base) abort
    return a:url =~# '^/' ? a:base . a:url : a:url
endfunction

function! s:Image(tag, base) abort
    let alt = matchstr(a:tag, '\<alt="\zs[^"]*')
    let src = s:Url(matchstr(a:tag, '\<src="\zs[^"]*'), a:base)
    " An empty alt text would hide the whole image where Markdown is concealed.
    return empty(src) ? '' : printf('![%s](%s)', empty(alt) ? 'image' : alt, src)
endfunction

" <ol> items as 1. 2. 3.
function! s:NumberItems(html) abort
    let s = a:html
    while 1
        let [block, start, end] = matchstrpos(s, '\c<ol\>[^>]*>\_.\{-}</ol>')
        if start < 0
            return s
        endif
        let parts = split(block, '\c<li\>[^>]*>', 1)
        let items = parts[0]
        for i in range(1, len(parts) - 1)
            let items .= "\n" . i . '. ' . parts[i]
        endfor
        let s = strpart(s, 0, start) . substitute(items, '\c</\=ol\>[^>]*>', "\n\x01\n", 'g')
                    \ . strpart(s, end)
    endwhile
endfunction

" The description as Markdown lines: paragraphs and lists separated by one
" empty line, examples as fenced code blocks. Relative links and images
" point at {base} (e.g. https://leetcode.com).
function! leetcode#html#ToMarkdown(html, ...) abort
    let base = get(a:, 1, '')
    let s:kept = []
    let s = substitute(a:html, '\r\n\=', '\n', 'g')
    let s = substitute(s, '\c<\(script\|style\)\>\_.\{-}</\1>', '', 'g')
    let s = substitute(s, '\c<pre\>[^>]*>\(\_.\{-}\)</pre>', '\=s:Keep("pre", submatch(1))', 'g')
    let s = substitute(s, '\c<code\>[^>]*>\(\_.\{-}\)</code>', '\=s:Keep("code", submatch(1))', 'g')
    let s = substitute(s, '&nbsp;\|&#160;\|' . nr2char(160), ' ', 'g')
    " A literal * in the text would start emphasis.
    let s = substitute(s, '\*', '\\*', 'g')
    let s = substitute(s, '\c<br\s*/\=>', '\n', 'g')
    let s = substitute(s, '\c<sup>\(\_.\{-}\)</sup>', '^\1', 'g')
    let s = substitute(s, '\c<sub>\(\_.\{-}\)</sub>', '_\1', 'g')
    let s = substitute(s, '\c<\(strong\|b\)\>[^>]*>\(\s*\)\(\_.\{-}\)\(\s*\)</\1>',
                \ '\=s:Emphasis("**", submatch(2), submatch(3), submatch(4))', 'g')
    let s = substitute(s, '\c<\(em\|i\)\>[^>]*>\(\s*\)\(\_.\{-}\)\(\s*\)</\1>',
                \ '\=s:Emphasis("*", submatch(2), submatch(3), submatch(4))', 'g')
    let s = substitute(s, '\c<img\>[^>]*>', '\=s:Image(submatch(0), base)', 'g')
    let s = substitute(s, '\c<a\>[^>]*\<href="\([^"]*\)"[^>]*>\(\_.\{-}\)</a>',
                \ '\="[" . submatch(2) . "](" . s:Url(submatch(1), base) . ")"', 'g')
    let s = s:NumberItems(s)
    let s = substitute(s, '\c<li\>[^>]*>', '\n- ', 'g')
    let s = substitute(s, '\c</li>', '\n', 'g')
    " Block boundaries get a line of their own, marked with \x01.
    let s = substitute(s, '\c</\=\(p\|div\|ul\|ol\|h[1-6]\|table\|tr\|blockquote\)\>[^>]*>',
                \ "\n\x01\n", 'g')
    let s = s:Decode(substitute(s, '<[^>]*>', '', 'g'))

    let result = []
    let gap = 0
    for line in split(s, "\n")
        if line ==# "\x01"
            let gap = !empty(result)
        elseif line =~# "^\x02\\d\\+\x02$"
            let code = split(s:kept[str2nr(line[1:])], "\n", 1)
            while !empty(code) && code[0] !~# '\S'
                call remove(code, 0)
            endwhile
            while !empty(code) && code[-1] !~# '\S'
                call remove(code, -1)
            endwhile
            call extend(result, (empty(result) ? [] : ['']) + ['```']
                        \ + map(code, 'substitute(v:val, ''\s\+$'', "", "")') + ['```'])
            let gap = 1
        elseif line =~# '\S'
            if gap
                call add(result, '')
            endif
            " Leading spaces would make an indented code block.
            let line = substitute(substitute(line, '^\s\+', '', ''), '\s\+$', '', '')
            " Runs of spaces count as one in HTML.
            let line = substitute(line, '\s\{2,}', ' ', 'g')
            call add(result, substitute(line, "\x03\\(\\d\\+\\)\x03",
                        \ '\=s:InlineCode(str2nr(submatch(1)))', 'g'))
            let gap = 0
        endif
    endfor
    return result
endfunction
