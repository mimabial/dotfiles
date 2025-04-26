let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/nvim.bak/lua/plugins/coding
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
if &shortmess =~ 'A'
  set shortmess=aoOA
else
  set shortmess=aoO
endif
badd +1 ~/nvim.bak/lua/config/settings.lua
badd +1 ~/nvim.bak/lua/core/autocmds.lua
badd +1 ~/nvim.bak/lua/core/keymaps.lua
badd +1 ~/nvim.bak/lua/core/options.lua
badd +1 ~/nvim.bak/lua/core/utils.lua
badd +1 ~/nvim.bak/lua/plugins/coding/ai.lua
badd +146 ~/nvim.bak/lua/plugins/coding/snippets.lua
badd +1 ~/nvim.bak/lua/plugins/coding/completions.lua
badd +1 ~/nvim.bak/lua/plugins/coding/init.lua
badd +1 ~/nvim.bak/lua/plugins/coding/refactoring.lua
badd +1 ~/nvim.bak/lua/plugins/editor/init.lua
badd +1 ~/nvim.bak/lua/plugins/editor/navigation.lua
badd +1 ~/nvim.bak/lua/plugins/editor/text-objects.lua
badd +1 ~/nvim.bak/lua/plugins/langs/go.lua
badd +1 ~/nvim.bak/lua/plugins/langs/init.lua
badd +1 ~/nvim.bak/lua/plugins/langs/lua.lua
badd +1 ~/nvim.bak/lua/plugins/langs/python.lua
badd +1 ~/nvim.bak/lua/plugins/langs/rust.lua
badd +1 ~/nvim.bak/lua/plugins/langs/web.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/formatters.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/init.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/keymaps.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/servers.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/linters.lua
badd +1 ~/nvim.bak/lua/plugins/lsp/ui.lua
badd +1 ~/nvim.bak/lua/plugins/tools/database.lua
badd +1 ~/nvim.bak/lua/plugins/tools/debug.lua
badd +1 ~/nvim.bak/lua/plugins/tools/git.lua
badd +1 ~/nvim.bak/lua/plugins/tools/init.lua
badd +1 ~/nvim.bak/lua/plugins/tools/terminal.lua
badd +1 ~/nvim.bak/lua/plugins/ui/colorscheme.lua
badd +1 ~/nvim.bak/lua/plugins/ui/dashboard.lua
badd +1 ~/nvim.bak/lua/plugins/ui/init.lua
badd +1 ~/nvim.bak/lua/plugins/ui/statusline.lua
badd +1 ~/nvim.bak/lua/plugins/util/init.lua
badd +1 ~/nvim.bak/lua/plugins/util/telescope.lua
badd +1 ~/nvim.bak/lua/plugins/util/treesitter.lua
badd +1 ~/nvim.bak/lua/plugins/init.lua
argglobal
%argdel
$argadd .
wincmd t
let s:save_winminheight = &winminheight
let s:save_winminwidth = &winminwidth
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let &winminheight = s:save_winminheight
let &winminwidth = s:save_winminwidth
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
set hlsearch
nohlsearch
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
