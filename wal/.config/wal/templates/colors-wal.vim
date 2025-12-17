let g:colors_name = 'pywal16'

hi clear
if exists('syntax_on')
    syntax reset
endif

hi Normal guifg={foreground} guibg={background}
hi Comment guifg={color8}
hi Constant guifg={color1}
hi String guifg={color2}
hi Identifier guifg={color4}
hi Function guifg={color4}
hi Statement guifg={color5}
hi PreProc guifg={color6}
hi Type guifg={color3}
hi Special guifg={color1}
hi Error guifg={foreground} guibg={color1}
hi Todo guifg={background} guibg={color3}
hi LineNr guifg={color8} guibg={background}
hi CursorLineNr guifg={color15} guibg={color8}
hi Visual guibg={color8}
hi Search guifg={background} guibg={color3}
hi IncSearch guifg={background} guibg={color4}
hi StatusLine guifg={foreground} guibg={color8}
hi StatusLineNC guifg={color8} guibg={background}
hi VertSplit guifg={color8} guibg={background}
hi Pmenu guibg={color8} guifg={foreground}
hi PmenuSel guibg={color4} guifg={background}
