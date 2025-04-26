-- ~/.config/nvim/lua/core/keymaps.lua
-- Global keymaps

-- Helper function for mapping keys
local function map(mode, lhs, rhs, opts)
  opts = opts or {}
  opts.silent = opts.silent ~= false -- Silent by default
  vim.keymap.set(mode, lhs, rhs, opts)
end

-- Better window navigation with Ctrl + hjkl
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Navigate Left" })
map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "Navigate Down" })
map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "Navigate Up" })
map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "Navigate Right" })
map("n", "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", { desc = "Navigate Previous" })

-- Buffer navigation
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous Buffer" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous Buffer" })
map("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
map("n", "[B", "<cmd>BufferLineMovePrev<cr>", { desc = "Move Buffer Prev" })
map("n", "]B", "<cmd>BufferLineMoveNext<cr>", { desc = "Move Buffer Next" })

-- Clear search highlighting
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear Search Highlight" })

-- Center cursor when moving
map("n", "<C-d>", "<C-d>zz", { desc = "Half Page Down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half Page Up" })
map("n", "n", "nzzzv", { desc = "Next Search Result" })
map("n", "N", "Nzzzv", { desc = "Previous Search Result" })

-- Preserve paste buffer when pasting over selection
map("x", "p", [["_dP]], { desc = "Paste Without Yanking" })

-- Delete without yanking
map({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete Without Yanking" })

-- Open file explorer
map("n", "-", "<cmd>Oil<CR>", { desc = "Open Parent Directory in Oil" })

-- Quick save and quit
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit" })

-- Diagnostic navigation
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous Diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next Diagnostic" })
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics (Trouble)" })
map("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer Diagnostics (Trouble)" })

-- Git navigation
map("n", "]h", function()
  if vim.wo.diff then
    vim.cmd.normal({ "]c", bang = true })
  else
    require("gitsigns").nav_hunk("next")
  end
end, { desc = "Next Git Hunk" })
map("n", "[h", function()
  if vim.wo.diff then
    vim.cmd.normal({ "[c", bang = true })
  else
    require("gitsigns").nav_hunk("prev")
  end
end, { desc = "Previous Git Hunk" })

-- File browser
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "Toggle Explorer" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find Files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "Find Text (Live Grep)" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Find Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Find Help" })

-- Jump to using Flash
map({ "n", "x", "o" }, "s", function()
  require("flash").jump()
end, { desc = "Flash Jump" })
map({ "n", "o", "x" }, "S", function()
  require("flash").treesitter()
end, { desc = "Flash Treesitter" })

-- Buffer operations
map("n", "<leader>bd", function()
  require("bufdelete").bufdelete(0)
end, { desc = "Delete Buffer" })
map("n", "<leader>bD", function()
  require("bufdelete").bufdelete(0, true)
end, { desc = "Force Delete Buffer" })
map("n", "<leader>bp", "<cmd>BufferLineTogglePin<CR>", { desc = "Toggle Pin" })
map("n", "<leader>br", "<cmd>BufferLineCloseRight<CR>", { desc = "Delete Buffers to the Right" })
map("n", "<leader>bl", "<cmd>BufferLineCloseLeft<CR>", { desc = "Delete Buffers to the Left" })

-- Window operations (using <leader>w prefix)
map("n", "<leader>wv", "<cmd>vsplit<CR>", { desc = "Split Vertical" })
map("n", "<leader>ws", "<cmd>split<CR>", { desc = "Split Horizontal" })
map("n", "<leader>wc", "<cmd>close<CR>", { desc = "Close Window" })
map("n", "<leader>wo", "<cmd>only<CR>", { desc = "Close Other Windows" })
map("n", "<leader>wr", "<C-w>r", { desc = "Rotate Windows" })
map("n", "<leader>wm", "<cmd>MaximizerToggle<CR>", { desc = "Toggle Maximize" })

-- LSP related keymaps
-- (These are defined in plugins/lsp/init.lua with LSP setup)

-- Terminal
map("t", "<Esc>", "<C-\\><C-n>", { desc = "Exit Terminal Mode" })

-- Global terminal toggle
map({ "n", "t" }, "<C-/>", function()
  require("toggleterm").toggle(1, nil)
end, { desc = "Toggle Terminal" })
map({ "n", "t" }, "<C-_>", function()
  require("toggleterm").toggle(1, nil)
end, { desc = "Toggle Terminal" }) -- For some keyboards

-- Resize with arrows
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Increase Window Height" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Decrease Window Height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease Window Width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase Window Width" })
