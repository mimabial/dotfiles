let mapleader = " "

syntax on "parser

filetype plugin indent on

set number
set relativenumber

" nvim defaults
set tabstop=2        
set shiftwidth=2     
set expandtab        

set hlsearch "hilight search, :nohl to remove

set t_Co=256 "terminal colors

set wildmenu " auto completion, trigger with <C-n> 


let s:VIM_DIR = fnamemodify($MYVIMRC, ':h')
if filereadable(s:VIM_DIR . '/colors/pywal16.vim')
    colorscheme pywal16
endif
