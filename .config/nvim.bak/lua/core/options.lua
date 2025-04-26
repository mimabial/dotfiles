-- ~/.config/nvim/lua/core/options.lua
-- Neovim options configuration

local opt = vim.opt
local g = vim.g

-- Leader key
g.mapleader = " "
g.maplocalleader = " "

-- UI
opt.number = true -- Show line numbers
opt.relativenumber = true -- Relative line numbers
opt.signcolumn = "yes" -- Always show sign column
opt.cursorline = true -- Highlight current line
opt.termguicolors = true -- True color support
opt.showmode = false -- Don't show mode (shown in statusline)
opt.showtabline = 2 -- Always show tabline
opt.laststatus = 3 -- Global status line
opt.cmdheight = 1 -- Command line height
opt.title = true -- Set window title
opt.scrolloff = 5 -- Keep 5 lines above/below cursor
opt.sidescrolloff = 5 -- Keep 5 columns left/right of cursor
opt.wrap = false -- Don't wrap lines
opt.linebreak = true -- Break lines at word boundaries
opt.conceallevel = 0 -- Don't hide characters
opt.list = true -- Show some invisible characters
opt.listchars = { -- Configure invisible characters
  tab = "→ ",
  trail = "·",
  extends = "»",
  precedes = "«",
  nbsp = "␣",
}

-- Editing
opt.expandtab = true -- Use spaces instead of tabs
opt.shiftwidth = 2 -- Size of an indent
opt.tabstop = 2 -- Number of spaces tabs count for
opt.smartindent = true -- Smart autoindenting
opt.autoindent = true -- Copy indent from current line
opt.shiftround = true -- Round indent to multiple of shiftwidth
opt.virtualedit = "block" -- Allow going past end of line in visual block mode
opt.clipboard = "unnamedplus" -- Use system clipboard

-- Search
opt.ignorecase = true -- Ignore case in search patterns
opt.smartcase = true -- Override ignorecase when pattern has uppercase
opt.hlsearch = true -- Highlight search results
opt.incsearch = true -- Show search matches as you type

-- Files
opt.swapfile = false -- Don't use swapfile
opt.backup = false -- Don't keep backup files
opt.undofile = true -- Persistent undo
opt.undolevels = 10000 -- Maximum number of changes that can be undone
opt.fileencoding = "utf-8" -- File encoding

-- Windows/splits
opt.splitbelow = true -- Put new windows below current
opt.splitright = true -- Put new windows right of current

-- Performance
opt.updatetime = 250 -- Update time for CursorHold event (ms)
opt.timeoutlen = 300 -- Time to wait for mapped sequence to complete (ms)
opt.redrawtime = 1500 -- Time for redrawing the display (ms)
opt.history = 200 -- Number of commands to remember
opt.shadafile = "NONE" -- Don't read or write shada file on startup

-- Completion
opt.completeopt = { "menuone", "noselect" } -- Completion options
opt.pumheight = 10 -- Maximum number of items in popup menu
opt.wildmenu = true -- Command-line completion
opt.wildmode = "longest:full,full" -- Complete longest common string, then each full match

-- Mouse
opt.mouse = "a" -- Enable mouse in all modes

-- Global statusline
opt.laststatus = 3 -- Global statusline

-- Netrw (disabled, using neo-tree instead)
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1
