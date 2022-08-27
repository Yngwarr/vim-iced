let s:save_cpo = &cpoptions
set cpoptions&vim

let s:V = vital#iced#new()
let s:L = s:V.import('Data.List')

let s:kondo = {
      \ 'job_out': '',
      \ 'option': '',
      \ 'user_dir': '',
      \ 'lint_opts': '',
      \ 'cache_dir': '',
      \ '__is_analyzing': v:false,
      \ }

function! s:temp_name(name) abort
  return printf('%s.tmp', a:name)
endfunction

function! s:rename_temp_file(base_name) abort
  call rename(s:temp_name(a:base_name), a:base_name)
endfunction

" -------------------
" clj-kondo component
" -------------------

function! s:kondo.cache_name() abort
  return printf('%s/%s.json', self.cache_dir, substitute(self.user_dir, '/', '_', 'g'))
endfunction

function! s:analyze__optional_analyzed(cache_name, callback) abort dict
  let self.__is_analyzing = v:false
  return a:callback(a:cache_name)
endfunction

function! s:analyze__analyzed(callback, result) abort dict
  let cache_name = self.cache_name()
  call s:rename_temp_file(cache_name)

  let AnalyzedFn = funcref(
        \ 's:analyze__optional_analyzed',
        \ [cache_name, a:callback],
        \ self)
  if has_key(self.option, 'analyzed')
    return self.option.analyzed(cache_name, AnalyzedFn)
  endif

  return AnalyzedFn()
endfunction

function! s:kondo.analyze(callback) abort
  if !g:iced_enable_clj_kondo_analysis | return | endif

  if self.__is_analyzing
    return a:callback({'warning': 'clj-kondo: is_analyzing'})
  endif

  let self.__is_analyzing = v:true
  let config = g:iced_enable_clj_kondo_local_analysis
       \ ? '{:output {:analysis {:protocol-impls true :locals true :keywords true} :format :json}}'
       \ : '{:output {:analysis {:protocol-impls true} :format :json}}'

  " NOTE: Using `writefile` will freeze vim/nvim just a little
  let command = ['sh', '-c', printf('clj-kondo --parallel %s --config ''%s'' > %s',
        \ self.lint_opts,
        \ config,
        \ s:temp_name(self.cache_name()),
        \ )]

  call self.job_out.redir(command, funcref('s:analyze__analyzed', [a:callback], self))
endfunction

function! s:kondo.is_analyzed() abort
  if !g:iced_enable_clj_kondo_analysis | return 0 | endif

  let cache_name = self.cache_name()
  return filereadable(cache_name)
endfunction

function! s:kondo.is_analyzing() abort
  if !g:iced_enable_clj_kondo_analysis | return 0 | endif
  return self.__is_analyzing
endfunction

function! s:kondo.analysis() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif

  let cache_name = self.cache_name()
  if !filereadable(cache_name)
    return {'error': printf('clj-kondo: file not readable: %s', cache_name)}
  endif

  let res = readfile(cache_name)
  if empty(res)
    return {'error': 'clj-kondo: empty file'}
  endif

  return get(json_decode(res[0]), 'analysis', {})
endfunction

function! s:kondo.namespace_usages() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif

  if has_key(self.option, 'namespace_usages')
    return self.option.namespace_usages()
  endif

  let ana = self.analysis()
  return (has_key(ana, 'namespace-usages'))
        \ ? ana['namespace-usages']
        \ : []
endfunction

function! s:kondo.namespace_definitions() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif

  if has_key(self.option, 'namespace_definitions')
    return self.option.namespace_definitions()
  endif

  let ana = self.analysis()
  return get(ana, 'namespace-definitions', [])
endfunction

function! s:kondo.local_usages() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif
  if !g:iced_enable_clj_kondo_local_analysis
    return {'error': 'clj-kondo local analysis: disabled'}
  endif

  if has_key(self.option, 'local_usages')
    return self.option.local_usages()
  endif

  let ana = self.analysis()
  return get(ana, 'local-usages', [])
endfunction

function! s:kondo.local_definitions() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif
  if !g:iced_enable_clj_kondo_local_analysis
    return {'error': 'clj-kondo local analysis: disabled'}
  endif

  if has_key(self.option, 'local_definitions')
    return self.option.local_definitions()
  endif

  let ana = self.analysis()
  return get(ana, 'locals', [])
endfunction

function! s:kondo.keywords() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif
  if !g:iced_enable_clj_kondo_local_analysis
    return {'error': 'clj-kondo local analysis: disabled'}
  endif

  if has_key(self.option, 'keywords')
    return self.option.keywords()
  endif

  let ana = self.analysis()
  return get(ana, 'keywords', [])
endfunction

function! s:kondo.keyword_usages(kw_name) abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif
  if !g:iced_enable_clj_kondo_local_analysis
    return {'error': 'clj-kondo local analysis: disabled'}
  endif

  if has_key(self.option, 'keyword_usages')
    return self.option.keyword_usages(a:kw_name)
  endif

  let ns = ''
  let name = ''
  let idx = stridx(a:kw_name, '/')

  if idx != -1
    let ns = a:kw_name[0:idx-1]
    let name = a:kw_name[idx+1:]
  else
    let name = a:kw_name
  endif

  let kws = copy(self.keywords())
  if ! empty(ns)
    return filter(kws, {_, v -> get(v, 'ns', '') ==# ns && get(v, 'name', '') ==# name})
  else
    return filter(kws, {_, v -> get(v, 'name', '') ==# name})
  endif
endfunction

function! s:kondo.keyword_definition(filename, kw_name) abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif
  if !g:iced_enable_clj_kondo_local_analysis
    return {'error': 'clj-kondo local analysis: disabled'}
  endif

  if has_key(self.option, 'keyword_definition')
    return self.option.keyword_definition(a:filename, a:kw_name)
  endif

  let ns = ''
  let name = ''
  let kw_name = substitute(a:kw_name, '^:\+', '', 'g')
  let idx = stridx(kw_name, '/')

  if idx != -1
    let ns = kw_name[0:idx-1]
    let name = kw_name[idx+1:]
  else
    let name = kw_name
  endif

  let kws = copy(self.keywords())
  if ! empty(ns)
    let targets = filter(copy(kws), {_, v -> get(v, 'filename', '') ==# a:filename && get(v, 'alias', '') ==# ns && get(v, 'name', '') ==# name})
    if empty(targets) | return {} | endif

    let target_ns = get(targets[0], 'ns', '')
    let target_name = get(targets[0], 'name', '')

    let results = filter(copy(kws), {_, v -> get(v, 'ns', '') ==# target_ns && get(v, 'name', '') ==# target_name && get(v, 'reg', '') !=# '' })
    if empty(results) | return {} | endif
    return results[0]
  else
    let results = filter(kws, {_, v -> get(v, 'filename', '') ==# a:filename && get(v, 'alias') ==# '' && get(v, 'name', '') ==# name && get(v, 'reg', '') !=# ''})
    if empty(results) | return {} | endif
    return results[0]
  endif
endfunction

function! s:kondo.references(ns_name, var_name) abort
  if has_key(self.option, 'references')
    return self.option.references(a:ns_name, a:var_name)
  endif

  " Remove quote if exists
  let var_name = trim(a:var_name, "'")

  let ana = self.analysis()
  let usages = get(ana, 'var-usages', [])
  let usages = filter(usages, {_, usage ->
        \ (get(usage, 'to', '') ==# a:ns_name
        \  && get(usage, 'name', '') ==# var_name)})
  return sort(usages, {x, y -> (x['filename'] ==# y['filename']) ? 0 : (x['filename'] < y['filename']) ? -1 : 1})
endfunction

function! s:kondo.dependencies(ns_name, var_name) abort
  " Remove quote if exists
  let var_name = trim(a:var_name, "'")

  let ana = self.analysis()
  let usages = get(ana, 'var-usages', [])
  let definitions = get(ana, 'var-definitions', [])
  let dependencies = filter(usages, {_, usage ->
        \ (get(usage, 'from', '') ==# a:ns_name
        \  && get(usage, 'from-var', '') ==# var_name
        \  && get(usage, 'to', '') !=# 'clojure.core')})
  let deps_dict = iced#util#list_to_dict(dependencies,
        \ {d -> printf('%s/%s', get(d, 'to', ''), get(d, 'name', ''))}, {d -> v:true})

  let definitions = filter(definitions, {_, definition ->
        \ has_key(deps_dict, printf('%s/%s', get(definition, 'ns', ''), get(definition, 'name', '')))})
  return sort(definitions, {x, y -> (x['filename'] ==# y['filename']) ? 0 : (x['filename'] < y['filename']) ? -1 : 1})
endfunction

function! s:kondo.used_ns_list() abort
  let usages = self.namespace_usages()
  if empty(usages) | return [] | endif

  let result = map(usages, {_, v -> get(v, 'to', '')})
  let result = filter(result, {_, v -> v !=# ''})

  return s:L.uniq(result)
endfunction

function! s:kondo.ns_aliases(...) abort
  if has_key(self.option, 'ns_aliases')
    return call(self.option.ns_aliases, a:000)
  endif

  let from_ns = get(a:, 1, '')
  let usages = self.namespace_usages()
  let result = {}
  if empty(usages) | return result | endif

  for usage in usages
    let ns_name = get(usage, 'to', '')
    let alias_name = get(usage, 'alias', '')
    if empty(ns_name) || empty(alias_name)
      continue
    endif

    if !empty(from_ns) && usage['from'] !=# from_ns
      continue
    endif

    " Format similar to refactor-nrepl's `namespace-aliases` op
    let ns_list = get(result, alias_name, []) + [ns_name]
    let result[alias_name] = s:L.uniq(ns_list)
  endfor

  return result
endfunction

function! s:kondo.var_definition(ns_name, var_name) abort
  " Remove quote if exists
  let var_name = trim(a:var_name, "'")
  let ana = self.analysis()
  for d in get(ana, 'var-definitions', [])
    if get(d, 'ns', '') ==# a:ns_name
          \ && get(d, 'name', '') ==# var_name
      return d
    endif
  endfor
endfunction

function! s:kondo.local_definition(filename, row, name) abort
  if has_key(self.option, 'local_definition')
    return self.option.local_definition(a:filename, a:row, a:name)
  endif

  " Remove quote if exists
  let name = trim(a:name, "'")

  for usage in self.local_usages()
    if get(usage, 'filename', '') ==# a:filename
          \ && get(usage, 'row', 0) == a:row
          \ && get(usage, 'name', '') ==# name
      for definition in self.local_definitions()
        if get(definition, 'id') == get(usage, 'id')
          return definition
        endif
      endfor

      return {}
    endif
  endfor
endfunction

function! s:kondo.ns_path(ns_name) abort
  if has_key(self.option, 'ns_path')
    return self.option.ns_path(a:ns_name)
  endif

  let definitions = self.namespace_definitions()
  for definition in definitions
    if get(definition, 'name') ==# a:ns_name
      return get(definition, 'filename', '')
    endif
  endfor

  return ''
endfunction

function! s:kondo.ns_list() abort
  if has_key(self.option, 'ns_list')
    return self.option.ns_list()
  endif

  let definitions = self.namespace_definitions()
  let res = map(copy(definitions), {_, d -> get(d, 'name', '')})
  let res = filter(res, {_, s -> !empty(s)})
  return res
endfunction

function! s:kondo.protocols() abort
  if !g:iced_enable_clj_kondo_analysis
    return {'error': 'clj-kondo: disabled'}
  endif

  if has_key(self.option, 'protocols')
    return self.option.protocols()
  endif

  let ana = self.analysis()
  return get(ana, 'protocol-impls', [])
endfunction

function! s:kondo.protocol_implementations(protocol_ns, protocol_name, method_name) abort
  if has_key(self.option, 'protocol_implementations')
    return self.option.protocol_implementations(a:protocol_ns, a:protocol_name, a:method_name)
  endif

  let protocols = copy(self.protocols())
  if empty(a:method_name)
    call filter(protocols, {_, v ->
          \ get(v, 'protocol-ns') ==# a:protocol_ns
          \ && get(v, 'protocol-name') ==# a:protocol_name
          \ })
  else
    call filter(protocols, {_, v ->
          \ get(v, 'protocol-ns') ==# a:protocol_ns
          \ && get(v, 'protocol-name') ==# a:protocol_name
          \ && get(v, 'method-name') ==# a:method_name
          \ })
  endif
  return protocols
endfunction

function! iced#component#clj_kondo#start(this) abort
  call iced#util#debug('start', 'clj-kondo')

  if g:iced_enable_clj_kondo_analysis
        \ && !executable('clj-kondo')
    call iced#promise#sync(a:this['installer'].install, ['clj-kondo'], 30000)
  endif

  let s:kondo.job_out = a:this['job_out']
  let s:kondo.option = a:this['clj_kondo_option']
  let s:kondo.cache_dir = iced#cache#directory()

  let user_dir = iced#nrepl#system#user_dir()
  let s:kondo.user_dir = empty(user_dir) ? expand('%:p:h') : user_dir

  let analysis_dirs = (len(g:iced_clj_kondo_analysis_dirs) > 0)
        \ ? g:iced_clj_kondo_analysis_dirs
        \ : [user_dir]
  let s:kondo.lint_opts = join(map(copy(analysis_dirs), {_, dir -> printf('--lint %s', dir)}), ' ')

  return s:kondo
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
