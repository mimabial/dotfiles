let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/neocode
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
if &shortmess =~ 'A'
  set shortmess=aoOA
else
  set shortmess=aoO
endif
badd +1 ~/neocode/lua/core/options.lua
badd +1 ~/neocode/lua/core/utils.lua
badd +1 ~/neocode/lua/plugins/editor/init.lua
badd +1 ~/neocode/lua/plugins/editor/text-objects.lua
badd +1 ~/neocode/lua/plugins/editor/navigation.lua
badd +1 ~/neocode/lua/plugins/init.lua
badd +1 ~/neocode/lua/plugins/lsp/ui.lua
badd +1 ~/neocode/lua/plugins/tools/git.lua
badd +1 ~/neocode/lua/plugins/tools/terminal.lua
badd +1 ~/neocode/lua/plugins/tools/database.lua
badd +1 ~/neocode/lua/plugins/ui/colorscheme.lua
badd +137 ~/neocode/lua/plugins/ui/dashboard.lua
badd +1 ~/neocode/lua/plugins/ui/init.lua
badd +1 ~/neocode/lua/plugins/ui/statusline.lua
badd +77 ~/neocode/lua/plugins/util/init.lua
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
