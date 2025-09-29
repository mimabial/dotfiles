
if exists('g:loaded_wallbash') | finish | endif
let g:loaded_wallbash = 1


" Detect background based on terminal colors
if $BACKGROUND =~# 'light'
  set background=light
else
  set background=dark
endif

" hi clear
let g:colors_name = 'wallbash'

let s:t_Co = &t_Co

" Terminal color setup
if (has('termguicolors') && &termguicolors) || has('gui_running')
  let s:is_dark = &background == 'dark'

  " Define terminal colors based on the background
  if s:is_dark
    let g:terminal_ansi_colors = ['1E2222', 'A37665', '7AC2C2', '7AC297',
                                \ '65A38E', '9AE6B8', '9AE6E6', '0C0B0C',
                                \ '80978F', 'C28D7A', '9AE6E6', 'AAF0C6',
                                \ '7AC2A9', 'AAF0C6', 'AAF0F0', 'FFFFFF']
  else
    " Lighter colors for light theme
    let g:terminal_ansi_colors = ['FFFFFF', 'E6AE9A', 'AAF0F0', 'AAF0C6',
                                \ '9AE6CB', 'CCFFE0', 'CCFFFF', 'B2BCB6',
                                \ '0C0B0C', 'F0BDAA', 'CCFFFF', 'CCFFE0',
                                \ 'AAF0D8', 'CCFFE0', 'CCFFFF', '1E2222']
  endif

  " Nvim uses g:terminal_color_{0-15} instead
  for i in range(g:terminal_ansi_colors->len())
    let g:terminal_color_{i} = g:terminal_ansi_colors[i]
  endfor
endif

      " For Neovim compatibility
      if has('nvim')
        " Set Neovim specific terminal colors
        let g:terminal_color_0 = '#' . g:terminal_ansi_colors[0]
        let g:terminal_color_1 = '#' . g:terminal_ansi_colors[1]
        let g:terminal_color_2 = '#' . g:terminal_ansi_colors[2]
        let g:terminal_color_3 = '#' . g:terminal_ansi_colors[3]
        let g:terminal_color_4 = '#' . g:terminal_ansi_colors[4]
        let g:terminal_color_5 = '#' . g:terminal_ansi_colors[5]
        let g:terminal_color_6 = '#' . g:terminal_ansi_colors[6]
        let g:terminal_color_7 = '#' . g:terminal_ansi_colors[7]
        let g:terminal_color_8 = '#' . g:terminal_ansi_colors[8]
        let g:terminal_color_9 = '#' . g:terminal_ansi_colors[9]
        let g:terminal_color_10 = '#' . g:terminal_ansi_colors[10]
        let g:terminal_color_11 = '#' . g:terminal_ansi_colors[11]
        let g:terminal_color_12 = '#' . g:terminal_ansi_colors[12]
        let g:terminal_color_13 = '#' . g:terminal_ansi_colors[13]
        let g:terminal_color_14 = '#' . g:terminal_ansi_colors[14]
        let g:terminal_color_15 = '#' . g:terminal_ansi_colors[15]
      endif

" Function to dynamically invert colors for UI elements
function! s:inverse_color(color)
  " This function takes a hex color (without #) and returns its inverse
  " Convert hex to decimal values
  let r = str2nr(a:color[0:1], 16)
  let g = str2nr(a:color[2:3], 16)
  let b = str2nr(a:color[4:5], 16)

  " Calculate inverse (255 - value)
  let r_inv = 255 - r
  let g_inv = 255 - g
  let b_inv = 255 - b

  " Convert back to hex
  return printf('%02x%02x%02x', r_inv, g_inv, b_inv)
endfunction

" Function to be called for selection background
function! InverseSelectionBg()
  if &background == 'dark'
    return 'CCFFFF'
  else
    return '295243'
  endif
endfunction

" Add high-contrast dynamic selection highlighting using the inverse color function
augroup WallbashDynamicHighlight
  autocmd!
  " Update selection highlight when wallbash colors change
  autocmd ColorScheme wallbash call s:update_dynamic_highlights()
augroup END

function! s:update_dynamic_highlights()
  let l:bg_color = synIDattr(synIDtrans(hlID('Normal')), 'bg#')
  if l:bg_color != ''
    let l:bg_color = l:bg_color[1:] " Remove # from hex color
    let l:inverse = s:inverse_color(l:bg_color)

    " Apply inverse color to selection highlights
    execute 'highlight! CursorSelection guifg=' . l:bg_color . ' guibg=#' . l:inverse

    " Link dynamic highlights to various selection groups
    highlight! link NeoTreeCursorLine CursorSelection
    highlight! link TelescopeSelection CursorSelection
    highlight! link CmpItemSelected CursorSelection
    highlight! link PmenuSel CursorSelection
    highlight! link WinSeparator VertSplit
  endif
endfunction

" Make selection visible right away for current colorscheme
call s:update_dynamic_highlights()

" Conditional highlighting based on background
if &background == 'dark'
  " Base UI elements with transparent backgrounds
  hi Normal guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi Pmenu guibg=#B2BCB6 guifg=#FFFFFF gui=NONE cterm=NONE
  hi StatusLine guifg=#FFFFFF guibg=#B2BCB6 gui=NONE cterm=NONE
  hi StatusLineNC guifg=#131212 guibg=#80978F gui=NONE cterm=NONE
  hi VertSplit guifg=#65A3A3 guibg=NONE gui=NONE cterm=NONE
  hi LineNr guifg=#65A3A3 guibg=NONE gui=NONE cterm=NONE
  hi SignColumn guifg=NONE guibg=NONE gui=NONE cterm=NONE
  hi FoldColumn guifg=#131212 guibg=NONE gui=NONE cterm=NONE

  " NeoTree with transparent background including unfocused state
  hi NeoTreeNormal guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeFloatNormal guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeFloatBorder guifg=#65A3A3 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeWinSeparator guifg=#80978F guibg=NONE gui=NONE cterm=NONE

  " NeoTree with transparent background
  hi NeoTreeNormal guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeRootName guifg=#CCFFFF guibg=NONE gui=bold cterm=bold

  " TabLine highlighting with complementary accents
  hi TabLine guifg=#131212 guibg=#B2BCB6 gui=NONE cterm=NONE
  hi TabLineFill guifg=NONE guibg=NONE gui=NONE cterm=NONE
  hi TabLineSel guifg=#1E2222 guibg=#CCFFFF gui=bold cterm=bold
  hi TabLineSeparator guifg=#65A3A3 guibg=#B2BCB6 gui=NONE cterm=NONE

  " Interactive elements with dynamic contrast
  hi Search guifg=#80978F guibg=#AAF0F0 gui=NONE cterm=NONE
  hi Visual guifg=#80978F guibg=#9AE6E6 gui=NONE cterm=NONE
  hi MatchParen guifg=#80978F guibg=#CCFFFF gui=bold cterm=bold

  " Menu item hover highlight
  hi CmpItemAbbrMatch guifg=#CCFFFF guibg=NONE gui=bold cterm=bold
  hi CmpItemAbbrMatchFuzzy guifg=#AAF0F0 guibg=NONE gui=bold cterm=bold
  hi CmpItemMenu guifg=#131212 guibg=NONE gui=italic cterm=italic
  hi CmpItemAbbr guifg=#FFFFFF guibg=NONE gui=NONE cterm=NONE
  hi CmpItemAbbrDeprecated guifg=#0C0B0C guibg=NONE gui=strikethrough cterm=strikethrough

  " Specific menu highlight groups
  hi WhichKey guifg=#CCFFFF guibg=NONE gui=NONE cterm=NONE
  hi WhichKeySeparator guifg=#0C0B0C guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyGroup guifg=#9AE6E6 guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyDesc guifg=#AAF0F0 guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyFloat guibg=#80978F guifg=NONE gui=NONE cterm=NONE

  " Selection and hover highlights with inverted colors
  hi CursorColumn guifg=NONE guibg=#B2BCB6 gui=NONE cterm=NONE
  hi Cursor guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi lCursor guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi CursorIM guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi TermCursor guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi TermCursorNC guibg=#131212 guifg=#1E2222 gui=NONE cterm=NONE
  hi CursorLine guibg=NONE ctermbg=NONE gui=underline cterm=underline
  hi CursorLineNr guifg=#CCFFFF guibg=NONE gui=bold cterm=bold

  hi QuickFixLine guifg=#80978F guibg=#9AE6E6 gui=NONE cterm=NONE
  hi IncSearch guifg=#80978F guibg=#CCFFFF gui=NONE cterm=NONE
  hi NormalNC guibg=#80978F guifg=#131212 gui=NONE cterm=NONE
  hi Directory guifg=#AAF0F0 guibg=NONE gui=NONE cterm=NONE
  hi WildMenu guifg=#80978F guibg=#CCFFFF gui=bold cterm=bold

  " Add highlight groups for focused items with inverted colors
  hi CursorLineFold guifg=#CCFFFF guibg=#80978F gui=NONE cterm=NONE
  hi FoldColumn guifg=#131212 guibg=NONE gui=NONE cterm=NONE
  hi Folded guifg=#FFFFFF guibg=#B2BCB6 gui=italic cterm=italic

  " File explorer specific highlights
  hi NeoTreeNormal guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#FFFFFF gui=NONE cterm=NONE
  hi NeoTreeRootName guifg=#CCFFFF guibg=NONE gui=bold cterm=bold
  hi NeoTreeFileName guifg=#FFFFFF guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeFileIcon guifg=#AAF0F0 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeDirectoryName guifg=#AAF0F0 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeDirectoryIcon guifg=#AAF0F0 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitModified guifg=#9AE6E6 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitAdded guifg=#7AC2C2 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitDeleted guifg=#A37665 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitUntracked guifg=#7AC297 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeIndentMarker guifg=#578F8F guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeSymbolicLinkTarget guifg=#9AE6E6 guibg=NONE gui=NONE cterm=NONE

  " File explorer cursor highlights with strong contrast
  " hi NeoTreeCursorLine guibg=#9AE6E6 guifg=#1E2222 gui=bold cterm=bold
  " hi! link NeoTreeCursor NeoTreeCursorLine
  " hi! link NeoTreeCursorLineSign NeoTreeCursorLine

  " Use wallbash colors for explorer snack in dark mode
  hi WinBar guifg=#FFFFFF guibg=#B2BCB6 gui=bold cterm=bold
  hi WinBarNC guifg=#131212 guibg=#80978F gui=NONE cterm=NONE
  hi ExplorerSnack guibg=#CCFFFF guifg=#1E2222 gui=bold cterm=bold
  hi BufferTabpageFill guibg=#1E2222 guifg=#0C0B0C gui=NONE cterm=NONE
  hi BufferCurrent guifg=#FFFFFF guibg=#CCFFFF gui=bold cterm=bold
  hi BufferCurrentMod guifg=#FFFFFF guibg=#9AE6E6 gui=bold cterm=bold
  hi BufferCurrentSign guifg=#CCFFFF guibg=#80978F gui=NONE cterm=NONE
  hi BufferVisible guifg=#FFFFFF guibg=#B2BCB6 gui=NONE cterm=NONE
  hi BufferVisibleMod guifg=#131212 guibg=#B2BCB6 gui=NONE cterm=NONE
  hi BufferVisibleSign guifg=#9AE6E6 guibg=#80978F gui=NONE cterm=NONE
  hi BufferInactive guifg=#0C0B0C guibg=#80978F gui=NONE cterm=NONE
  hi BufferInactiveMod guifg=#65A3A3 guibg=#80978F gui=NONE cterm=NONE
  hi BufferInactiveSign guifg=#65A3A3 guibg=#80978F gui=NONE cterm=NONE

  " Fix link colors to make them more visible
  hi link Hyperlink NONE
  hi link markdownLinkText NONE
  hi Underlined guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline
  hi Special guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownUrl guifg=#FF00FF guibg=NONE gui=underline cterm=underline
  hi markdownLinkText guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi htmlLink guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline

  " Add more direct highlights for badges in markdown
  hi markdownH1 guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownLinkDelimiter guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownLinkTextDelimiter guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownIdDeclaration guifg=#FF00FF guibg=NONE gui=bold cterm=bold
else
  " Light theme with transparent backgrounds
  hi Normal guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi Pmenu guibg=#0C0B0C guifg=#1E2222 gui=NONE cterm=NONE
  hi StatusLine guifg=#FFFFFF guibg=#4B7D5F gui=NONE cterm=NONE
  hi StatusLineNC guifg=#1E2222 guibg=#131212 gui=NONE cterm=NONE
  hi VertSplit guifg=#4B7D5F guibg=NONE gui=NONE cterm=NONE
  hi LineNr guifg=#4B7D5F guibg=NONE gui=NONE cterm=NONE
  hi SignColumn guifg=NONE guibg=NONE gui=NONE cterm=NONE
  hi FoldColumn guifg=#80978F guibg=NONE gui=NONE cterm=NONE

  " NeoTree with transparent background including unfocused state
  hi NeoTreeNormal guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeFloatNormal guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeFloatBorder guifg=#4B7D6C guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeWinSeparator guifg=#131212 guibg=NONE gui=NONE cterm=NONE

  " NeoTree with transparent background
  hi NeoTreeNormal guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeRootName guifg=#295243 guibg=NONE gui=bold cterm=bold

  " TabLine highlighting with complementary accents
  hi TabLine guifg=#1E2222 guibg=#131212 gui=NONE cterm=NONE
  hi TabLineFill guifg=NONE guibg=NONE gui=NONE cterm=NONE
  hi TabLineSel guifg=#FFFFFF guibg=#295243 gui=bold cterm=bold
  hi TabLineSeparator guifg=#4B7D5F guibg=#131212 gui=NONE cterm=NONE

  " Interactive elements with complementary contrast
  hi Search guifg=#FFFFFF guibg=#3A6B5A gui=NONE cterm=NONE
  hi Visual guifg=#FFFFFF guibg=#4B7D5F gui=NONE cterm=NONE
  hi MatchParen guifg=#FFFFFF guibg=#295243 gui=bold cterm=bold

  " Menu item hover highlight
  hi CmpItemAbbrMatch guifg=#295243 guibg=NONE gui=bold cterm=bold
  hi CmpItemAbbrMatchFuzzy guifg=#3A6B5A guibg=NONE gui=bold cterm=bold
  hi CmpItemMenu guifg=#80978F guibg=NONE gui=italic cterm=italic
  hi CmpItemAbbr guifg=#1E2222 guibg=NONE gui=NONE cterm=NONE
  hi CmpItemAbbrDeprecated guifg=#B2BCB6 guibg=NONE gui=strikethrough cterm=strikethrough

  " Specific menu highlight groups
  hi WhichKey guifg=#295243 guibg=NONE gui=NONE cterm=NONE
  hi WhichKeySeparator guifg=#B2BCB6 guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyGroup guifg=#4B7D6C guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyDesc guifg=#3A6B5A guibg=NONE gui=NONE cterm=NONE
  hi WhichKeyFloat guibg=#131212 guifg=NONE gui=NONE cterm=NONE

  " Selection and hover highlights with inverted colors
  hi CursorColumn guifg=NONE guibg=#0C0B0C gui=NONE cterm=NONE
  hi Cursor guibg=#1E2222 guifg=#FFFFFF gui=NONE cterm=NONE
  hi lCursor guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi CursorIM guibg=#FFFFFF guifg=#1E2222 gui=NONE cterm=NONE
  hi TermCursor guibg=#1E2222 guifg=#FFFFFF gui=NONE cterm=NONE
  hi TermCursorNC guibg=#131212 guifg=#1E2222 gui=NONE cterm=NONE
  hi CursorLine guibg=NONE ctermbg=NONE gui=underline cterm=underline
  hi CursorLineNr guifg=#295243 guibg=NONE gui=bold cterm=bold

  hi QuickFixLine guifg=#FFFFFF guibg=#3A6B5A gui=NONE cterm=NONE
  hi IncSearch guifg=#FFFFFF guibg=#295243 gui=NONE cterm=NONE
  hi NormalNC guibg=#FFFFFF guifg=#80978F gui=NONE cterm=NONE
  hi Directory guifg=#295243 guibg=NONE gui=NONE cterm=NONE
  hi WildMenu guifg=#FFFFFF guibg=#295243 gui=bold cterm=bold

  " Add highlight groups for focused items with inverted colors
  hi CursorLineFold guifg=#295243 guibg=#FFFFFF gui=NONE cterm=NONE
  hi FoldColumn guifg=#80978F guibg=NONE gui=NONE cterm=NONE
  hi Folded guifg=#1E2222 guibg=#0C0B0C gui=italic cterm=italic

  " File explorer specific highlights
  hi NeoTreeNormal guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeEndOfBuffer guibg=NONE guifg=#1E2222 gui=NONE cterm=NONE
  hi NeoTreeRootName guifg=#295243 guibg=NONE gui=bold cterm=bold
  hi NeoTreeFileName guifg=#1E2222 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeFileIcon guifg=#3A6B5A guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeDirectoryName guifg=#3A6B5A guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeDirectoryIcon guifg=#3A6B5A guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitModified guifg=#4B7D6C guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitAdded guifg=#578F6D guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitDeleted guifg=#A37665 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeGitUntracked guifg=#7AC297 guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeIndentMarker guifg=#578F7B guibg=NONE gui=NONE cterm=NONE
  hi NeoTreeSymbolicLinkTarget guifg=#4B7D6C guibg=NONE gui=NONE cterm=NONE

  " File explorer cursor highlights with strong contrast
  " hi NeoTreeCursorLine guibg=#3A6B5A guifg=#FFFFFF gui=bold cterm=bold
  " hi! link NeoTreeCursor NeoTreeCursorLine
  " hi! link NeoTreeCursorLineSign NeoTreeCursorLine

  " Use wallbash colors for explorer snack in light mode
  hi WinBar guifg=#1E2222 guibg=#0C0B0C gui=bold cterm=bold
  hi WinBarNC guifg=#80978F guibg=#131212 gui=NONE cterm=NONE
  hi ExplorerSnack guibg=#295243 guifg=#FFFFFF gui=bold cterm=bold
  hi BufferTabpageFill guibg=#FFFFFF guifg=#B2BCB6 gui=NONE cterm=NONE
  hi BufferCurrent guifg=#FFFFFF guibg=#295243 gui=bold cterm=bold
  hi BufferCurrentMod guifg=#FFFFFF guibg=#4B7D6C gui=bold cterm=bold
  hi BufferCurrentSign guifg=#295243 guibg=#131212 gui=NONE cterm=NONE
  hi BufferVisible guifg=#1E2222 guibg=#0C0B0C gui=NONE cterm=NONE
  hi BufferVisibleMod guifg=#80978F guibg=#0C0B0C gui=NONE cterm=NONE
  hi BufferVisibleSign guifg=#4B7D6C guibg=#131212 gui=NONE cterm=NONE
  hi BufferInactive guifg=#B2BCB6 guibg=#131212 gui=NONE cterm=NONE
  hi BufferInactiveMod guifg=#65A38E guibg=#131212 gui=NONE cterm=NONE
  hi BufferInactiveSign guifg=#65A38E guibg=#131212 gui=NONE cterm=NONE

  " Fix link colors to make them more visible
  hi link Hyperlink NONE
  hi link markdownLinkText NONE
  hi Underlined guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline
  hi Special guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownUrl guifg=#FF00FF guibg=NONE gui=underline cterm=underline
  hi markdownLinkText guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi htmlLink guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline

  " Add more direct highlights for badges in markdown
  hi markdownH1 guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownLinkDelimiter guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownLinkTextDelimiter guifg=#FF00FF guibg=NONE gui=bold cterm=bold
  hi markdownIdDeclaration guifg=#FF00FF guibg=NONE gui=bold cterm=bold
endif

" UI elements that are the same in both themes with transparent backgrounds
hi NormalFloat guibg=NONE guifg=NONE gui=NONE cterm=NONE
hi FloatBorder guifg=#4B7D5F guibg=NONE gui=NONE cterm=NONE
hi SignColumn guifg=NONE guibg=NONE gui=NONE cterm=NONE
hi DiffAdd guifg=#FFFFFF guibg=#7AC2C2 gui=NONE cterm=NONE
hi DiffChange guifg=#FFFFFF guibg=#65A37E gui=NONE cterm=NONE
hi DiffDelete guifg=#FFFFFF guibg=#A37665 gui=NONE cterm=NONE
hi TabLineFill guifg=NONE guibg=NONE gui=NONE cterm=NONE

" Fix selection highlighting with proper color derivatives
hi TelescopeSelection guibg=#CCFFE0 guifg=#1E2222 gui=bold cterm=bold
hi TelescopeSelectionCaret guifg=#FFFFFF guibg=#CCFFE0 gui=bold cterm=bold
hi TelescopeMultiSelection guibg=#9AE6B8 guifg=#1E2222 gui=bold cterm=bold
hi TelescopeMatching guifg=#C28D7A guibg=NONE gui=bold cterm=bold

" Minimal fix for explorer selection highlighting
hi NeoTreeCursorLine guibg=#CCFFE0 guifg=#1E2222 gui=bold

" Fix for LazyVim menu selection highlighting
hi Visual guibg=#FFDACC guifg=#1E2222 gui=bold
hi CursorLine guibg=NONE ctermbg=NONE gui=underline cterm=underline
hi PmenuSel guibg=#FFDACC guifg=#1E2222 gui=bold
hi WildMenu guibg=#FFDACC guifg=#1E2222 gui=bold

" Create improved autocommands to ensure highlighting persists with NeoTree focus fixes
augroup WallbashSelectionFix
  autocmd!
  " Force these persistent highlights with transparent backgrounds where possible
  autocmd ColorScheme * if &background == 'dark' |
    \ hi Normal guibg=NONE |
    \ hi NeoTreeNormal guibg=NONE |
    \ hi SignColumn guibg=NONE |
    \ hi NormalFloat guibg=NONE |
    \ hi FloatBorder guibg=NONE |
    \ hi TabLineFill guibg=NONE |
    \ else |
    \ hi Normal guibg=NONE |
    \ hi NeoTreeNormal guibg=NONE |
    \ hi SignColumn guibg=NONE |
    \ hi NormalFloat guibg=NONE |
    \ hi FloatBorder guibg=NONE |
    \ hi TabLineFill guibg=NONE |
    \ endif

  " Force NeoTree background to be transparent even when unfocused
  autocmd WinEnter,WinLeave,BufEnter,BufLeave * if &ft == 'neo-tree' || &ft == 'NvimTree' |
    \ hi NeoTreeNormal guibg=NONE |
    \ hi NeoTreeEndOfBuffer guibg=NONE |
    \ endif

  " Fix NeoTree unfocus issue specifically in LazyVim
  autocmd VimEnter,ColorScheme * hi link NeoTreeNormalNC NeoTreeNormal

  " Make CursorLine less obtrusive by using underline instead of background
  autocmd ColorScheme * hi CursorLine guibg=NONE ctermbg=NONE gui=underline cterm=underline

  " Make links visible across modes
  autocmd ColorScheme * if &background == 'dark' |
    \ hi Underlined guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline |
    \ hi Special guifg=#FF00FF guibg=NONE gui=bold cterm=bold |
    \ else |
    \ hi Underlined guifg=#FF00FF guibg=NONE gui=bold,underline cterm=bold,underline |
    \ hi Special guifg=#FF00FF guibg=NONE gui=bold cterm=bold |
    \ endif

  " Fix markdown links specifically
  autocmd FileType markdown hi markdownUrl guifg=#FF00FF guibg=NONE gui=underline,bold
  autocmd FileType markdown hi markdownLinkText guifg=#FF00FF guibg=NONE gui=bold
  autocmd FileType markdown hi markdownIdDeclaration guifg=#FF00FF guibg=NONE gui=bold
  autocmd FileType markdown hi htmlLink guifg=#FF00FF guibg=NONE gui=bold,underline
augroup END

" Create a more aggressive fix for NeoTree background in LazyVim
augroup FixNeoTreeBackground
  autocmd!
  " Force NONE background for NeoTree at various points to override tokyonight fallback
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NeoTreeNormal guibg=NONE guifg=#FFFFFF ctermbg=NONE
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NeoTreeNormalNC guibg=NONE guifg=#131212 ctermbg=NONE
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NeoTreeEndOfBuffer guibg=NONE guifg=#FFFFFF ctermbg=NONE

  " Also fix NvimTree for NvChad
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NvimTreeNormal guibg=NONE guifg=#FFFFFF ctermbg=NONE
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NvimTreeNormalNC guibg=NONE guifg=#131212 ctermbg=NONE
  autocmd ColorScheme,VimEnter,WinEnter,BufEnter * hi NvimTreeEndOfBuffer guibg=NONE guifg=#FFFFFF ctermbg=NONE

  " Apply highlight based on current theme
  autocmd ColorScheme,VimEnter * if &background == 'dark' |
    \ hi NeoTreeCursorLine guibg=#CCFFE0 guifg=#1E2222 gui=bold cterm=bold |
    \ hi NvimTreeCursorLine guibg=#CCFFE0 guifg=#1E2222 gui=bold cterm=bold |
    \ else |
    \ hi NeoTreeCursorLine guibg=#295243 guifg=#FFFFFF gui=bold cterm=bold |
    \ hi NvimTreeCursorLine guibg=#295243 guifg=#FFFFFF gui=bold cterm=bold |
    \ endif

  " Force execution after other plugins have loaded
  autocmd VimEnter * doautocmd ColorScheme
augroup END

" Add custom autocommand specifically for LazyVim markdown links
augroup LazyVimMarkdownFix
  autocmd!
  " Force link visibility in LazyVim with stronger override
  autocmd FileType markdown,markdown.mdx,markdown.gfm hi! def link markdownUrl MagentaLink
  autocmd FileType markdown,markdown.mdx,markdown.gfm hi! def link markdownLinkText MagentaLink
  autocmd FileType markdown,markdown.mdx,markdown.gfm hi! def link markdownLink MagentaLink
  autocmd FileType markdown,markdown.mdx,markdown.gfm hi! def link markdownLinkDelimiter MagentaLink
  autocmd FileType markdown,markdown.mdx,markdown.gfm hi! MagentaLink guifg=#FF00FF gui=bold,underline

  " Apply when LazyVim is detected
  autocmd User LazyVimStarted doautocmd FileType markdown
  autocmd VimEnter * if exists('g:loaded_lazy') | doautocmd FileType markdown | endif
augroup END

" Add custom autocommand specifically for markdown files with links
augroup MarkdownLinkFix
  autocmd!
  " Use bright hardcoded magenta that will definitely be visible
  autocmd FileType markdown hi markdownUrl guifg=#FF00FF guibg=NONE gui=underline,bold
  autocmd FileType markdown hi markdownLinkText guifg=#FF00FF guibg=NONE gui=bold
  autocmd FileType markdown hi markdownIdDeclaration guifg=#FF00FF guibg=NONE gui=bold
  autocmd FileType markdown hi htmlLink guifg=#FF00FF guibg=NONE gui=bold,underline

  " Force these highlights right after vim loads
  autocmd VimEnter * if &ft == 'markdown' | doautocmd FileType markdown | endif
augroup END

" Remove possibly conflicting previous autocommands
augroup LazyVimFix
  autocmd!
augroup END

augroup MinimalExplorerFix
  autocmd!
augroup END
