let s:save_cpo = &cpo
set cpo&vim

let s:bufname = 'iced_error'

let g:iced#buffer#error#height = get(g:, 'iced#buffer#error#height', &previewheight)

function! s:initialize(bufnr) abort
  call setbufvar(a:bufnr, '&bufhidden', 'hide')
  call setbufvar(a:bufnr, '&buflisted', 0)
  call setbufvar(a:bufnr, '&buftype', 'nofile')
  call setbufvar(a:bufnr, '&filetype', 'clojure')
  call setbufvar(a:bufnr, '&swapfile', 0)
endfunction

function! iced#buffer#error#init() abort
  call iced#buffer#init(s:bufname, funcref('s:initialize'))
endfunction

function! iced#buffer#error#open() abort
  call iced#buffer#open(
      \ s:bufname,
      \ {'opener': 'split',
      \  'mods': 'belowright',
      \  'scroll_to_top': v:true,
      \  'height': g:iced#buffer#error#height})
endfunction

function! iced#buffer#error#show(text) abort
  if empty(a:text)
    call iced#buffer#close(s:bufname)
    return
  endif

  call iced#buffer#set_contents(s:bufname, a:text)
  call iced#buffer#error#open()
endfunction

function! iced#buffer#error#close() abort
  call iced#buffer#close(s:bufname)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
