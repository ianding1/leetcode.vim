" vim: sts=4 sw=4 expandtab

function! s:Compare(a, b) abort
    if a:a < a:b
        return -1
    elseif a:a == a:b
        return 0
    else
        return 1
    endif
endfunction

let s:state_to_int_map = {' ': 0, '?': 1, 'X': 2}

function! s:CompareByState(a, b) abort
    let a_state_val = s:state_to_int_map[a:a['state']]
    let b_state_val = s:state_to_int_map[a:b['state']]
    return s:Compare(a_state_val, b_state_val)
endfunction

function! s:CompareById(a, b) abort
    let a_id = str2nr(a:a['fid'])
    let b_id = str2nr(a:b['fid'])
    return s:Compare(a_id, b_id)
endfunction

function! s:CompareByTitle(a, b) abort
    return s:Compare(a:a['title'], a:b['title'])
endfunction

function! s:CompareByAcRate(a, b) abort
    return s:Compare(a:a['ac_rate'], a:b['ac_rate'])
endfunction

let s:level_to_int_map = {'Easy': 0, 'Medium': 1, 'Hard': 2}

function! s:CompareByLevel(a, b) abort
    let a_level_val = s:level_to_int_map[a:a['level']]
    let b_level_val = s:level_to_int_map[a:b['level']]
    return s:Compare(a_level_val, b_level_val)
endfunction

function! s:CompareByFrequency(a, b) abort
    return s:Compare(a:a['frequency'], a:b['frequency'])
endfunction

let s:compare_func_map = {
            \ 'state': function('s:CompareByState'),
            \ 'id': function('s:CompareById'),
            \ 'title': function('s:CompareByTitle'),
            \ 'ac_rate': function('s:CompareByAcRate'),
            \ 'level': function('s:CompareByLevel'),
            \ 'frequency': function('s:CompareByFrequency'),
            \ }

function! leetcode#sort#SortProblems(problems, sort_by_column)
    return sort(copy(a:problems), s:compare_func_map[a:sort_by_column])
endfunction
