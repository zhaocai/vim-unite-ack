" [TODO]( <zhaocai> 2011-12-25 03:12PM ) add ack action -> make unite collection

">=< Config [[[1 =============================================================
call unite#util#set_default('g:unite_source_ack_command', 'ack-grep')
call unite#util#set_default('g:unite_source_ack_default_opts', '-H --nocolor --nogroup')
call unite#util#set_default('g:unite_source_ack_use_regexp', 0)
call unite#util#set_default('g:unite_source_ack_ignore_case', 0)
call unite#util#set_default('g:unite_source_ack_enable_highlight', 1)
call unite#util#set_default('g:unite_source_ack_search_word_highlight', 'Search')
call unite#util#set_default('g:unite_source_ack_enable_print_cmd', 0)
call unite#util#set_default('g:unite_source_ack_targetdir_shortcut', {})
call unite#util#set_default('g:unite_source_ack_enable_convert_targetdir_shortcut', 0)

">=< Actions [[[1 ============================================================
let s:action_ack_file = {
            \   'description': 'ack this!',
            \   'is_quit': 1,
            \   'is_invalidate_cache': 1,
            \   'is_selectable': 1,
            \ }
fun! s:action_ack_file.func(candidates) "                                 [[[2
    call unite#start([
                    \['ack', map(copy(a:candidates),
                        \ 'substitute(v:val.action__path, "/$", "", "g")'),
                    \]
                    \], { 'no_quit' : 1 })
endf

let s:action_ack_directory = {
            \   'description': 'ack directory!',
            \   'is_quit': 1,
            \   'is_invalidate_cache': 1,
            \   'is_selectable': 1,
            \ }
fun! s:action_ack_directory.func(candidates) "                            [[[2
    call unite#start([
                    \['ack', map(copy(a:candidates), 'v:val.action__directory')]
                    \], { 'no_quit' : 1 })
endf
if executable(g:unite_source_ack_command) && unite#util#has_vimproc()
    call unite#custom_action('file,buffer', 'ack', s:action_ack_file)
    call unite#custom_action('file,buffer', 'ack_directory', s:action_ack_directory)
endif

">=< Source [[[1 =============================================================
let s:ack_source = {
            \ "name": "ack",
            \ "filters": ['converter_relative_word', 'matcher_default', 'sorter_default' ],
            \ "description": 'candidates from ack-grep',
            \ "hooks": {},
            \ "syntax": "uniteSource__Ack",
            \ }
fun! unite#sources#ack#define() "                                         [[[2
    return executable(g:unite_source_ack_command) && unite#util#has_vimproc() ?
                \ s:ack_source : []
endf

">=< Hooks [[[1 ==============================================================
fun! s:ack_source.hooks.on_init(args, context) "                          [[[2
	" ~ target ~                                                          [[[3
    if type(get(a:args, 0, '')) == type([])
        let default_target = join(get(a:args, 0, ''))
    else
        let default_target = get(a:args, 0, '')
    endif

    if default_target == ''
        let default_target = zlib#path#find_project_root()
    endif
    " [TODO]( <zhaocai> 2011-12-28 10:36PM ) mru target
    let target = input('Target: ', default_target, 'file')

    if target == '' || target ==# 'buffers'
        let target = join(map(filter(range(1, bufnr('$')), 'buflisted(v:val)'),
          \ 'unite#util#escape_file_searching(bufname(v:val))'))
    elseif target =~# '^\%(p\|project\)$'
        let target = zlib#path#find_project_root()
    elseif target == '%' || target == '#'
        let target = unite#util#escape_file_searching(bufname(target))
    elseif target =~# '^h\d$'
        let [ level ] = matchlist(target,'\vh(\d)$')[1:1]
        let target = unite#util#substitute_path_separator(
                    \ fnamemodify(bufname('%'), ":p" . repeat(':h',level)))
    elseif target == '**'
        let target = '*'
    else
        let target = get(g:unite_source_ack_targetdir_shortcut, target, target)
        if empty(target)
            let target = join(map(filter(range(1, bufnr('$')), 'buflisted(v:val)'),
                        \ 'unite#util#escape_file_searching(bufname(v:val))'))
        endif
    endif
    let a:context.source__target = split(target)

	" ~ input ~                                                           [[[3
	let a:context.source__input = get(a:args, 1, '')
	if a:context.source__input == ''
		let a:context.source__input = input('Pattern: ')
	endif

	" ~ extra opts ~                                                      [[[3
	let a:context.source__extra_opts = get(a:args, 2, '')
	if a:context.source__extra_opts != ''
		let a:context.source__extra_opts = ' ' . a:context.source__extra_opts
	endif
	let a:context.source__nr_async_update = 0
endf

fun! s:ack_source.hooks.on_syntax(args, context) "                        [[[2
    if !g:unite_source_ack_enable_highlight | return | endif
    if g:unite_source_ack_ignore_case
        syn case ignore
    endif

    execute "syntax match uniteSource__AckPattern '\\v"
                \ . a:context.source__input . "' containedin=uniteSource__Ack"

    execute 'highlight default link uniteSource__AckPattern '
                \ . g:unite_source_ack_search_word_highlight

	syntax region uniteSource__AckLineNrBlock start="\[\d\+" end="\]" transparent containedin=uniteSource__Ack contains=uniteSource__AckLineNr
    syntax match uniteSource__AckLineNr '\d\+' containedin=uniteSource__AckLineNrBlock

    execute 'highlight default link uniteSource__AckLineNr ' . 'LineNr'

endf

fun! s:ack_source.hooks.on_close(args, context) "                         [[[2
    if has_key(a:context, 'source__proc')
        call a:context.source__proc.waitpid()
    endif
endf

">=< Gather Candidates [[[1 ==================================================
fun! s:ack_source.gather_candidates(args, context) "                      [[[2
    if empty(a:context.source__target)
                \ || a:context.source__input == ''
        let a:context.is_async = 0
        call unite#print_message('[ack] Completed.')
        return []
    endif

    if a:context.is_redraw
        let a:context.is_async = 1
    endif
	let cmdline = printf('%s %s%s%s%s ''%s'' %s',
				\   g:unite_source_ack_command,
				\   g:unite_source_ack_default_opts,
				\   g:unite_source_ack_ignore_case ? ' -i ' : '',
				\   a:context.source__extra_opts,
				\   g:unite_source_ack_use_regexp ? ' --match' : '',
				\   substitute(a:context.source__input, "'", "''", 'g'),
				\   join(a:context.source__target),
				\)
	let a:context.source__proc = vimproc#pgroup_open(cmdline,1)
	let a:context.source__cmdline = cmdline

	" Close handles.
	call a:context.source__proc.stdin.close()
	call a:context.source__proc.stderr.close()

	return []

endf

fun! s:ack_source.async_gather_candidates(args, context) "                [[[2
	call unite#clear_message()
    if g:unite_source_ack_enable_print_cmd
        call unite#print_message('[ack] Command-line: ' . a:context.source__cmdline)
    endif

	let a:context.source__nr_async_update += 1

	let stdout = a:context.source__proc.stdout
	if stdout.eof
		" Disable async.
		call unite#print_message('[ack] Completed.')
		let a:context.is_async = 0
	else
		call unite#print_message('[ack] In Progess' . repeat('.',a:context.source__nr_async_update))
	endif

    " let lines = map(stdout.read_lines(-1, 1000),
				\ 'iconv(v:val, &termencoding, &encoding)')
    let lines = stdout.read_lines(-1, 1000)
    let candidates = []
    for line in lines
		if empty(line)
			continue
		endif
        let [fname, lineno, text ] = matchlist(line,'\v(.{-}):(\d+):(.*)$')[1:3]
		let word = fname . ' [' . lineno . "] " . text
        call add(candidates, {
                    \ "word": word ,
                    \ "source": "ack",
                    \ "kind": "jump_list",
                    \ "action__path": fname,
                    \ "action__line": lineno,
                    \ "action__text": text,
                    \ } )
    endfor
    return candidates
endf


">=< Modeline [[[1 ===========================================================
" vim: set ft=vim ts=4 sw=4 tw=78 fdm=marker fmr=[[[,]]] fdl=1 :
