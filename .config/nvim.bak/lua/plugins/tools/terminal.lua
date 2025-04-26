-- Terminal integration configuration
-- Sets up a terminal within Neovim with advanced features

return {
  -- Toggleterm: better terminal integration
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      { "<C-\\>", "<cmd>ToggleTerm<CR>", desc = "Toggle Terminal" },
      { "<leader>tf", "<cmd>ToggleTerm direction=float<CR>", desc = "Terminal Float" },
      { "<leader>th", "<cmd>ToggleTerm direction=horizontal<CR>", desc = "Terminal Horizontal" },
      { "<leader>tv", "<cmd>ToggleTerm direction=vertical<CR>", desc = "Terminal Vertical" },
      { "<leader>tt", "<cmd>ToggleTerm direction=tab<CR>", desc = "Terminal Tab" },
      {
        "<leader>tg",
        function()
          require("neocode.utils").toggle_lazygit()
        end,
        desc = "LazyGit",
      },
    },
    opts = {
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return vim.o.columns * 0.4
        end
      end,
      on_open = function()
        -- Disable line numbers in terminal
        vim.cmd("setlocal nonu nornu signcolumn=no")
      end,
      shade_terminals = false,
      shading_factor = 0.3,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      persist_mode = true,
      direction = "horizontal",
      close_on_exit = true,
      shell = vim.o.shell,
      auto_scroll = true,
      float_opts = {
        border = "curved",
        winblend = 3,
      },
      winbar = {
        enabled = true,
        name_formatter = function(term)
          return " Terminal " .. term.name
        end,
      },
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)

      -- Create utility functions for terminal commands
      local utils_path = "lua/neocode/utils.lua"
      local utils_exists = vim.fn.filereadable(vim.fn.stdpath("config") .. "/" .. utils_path)

      if not utils_exists then
        -- Create utils module if it doesn't exist
        local utils_dir = vim.fn.stdpath("config") .. "/lua/neocode"
        vim.fn.mkdir(utils_dir, "p")

        local utils_file = io.open(utils_dir .. "/utils.lua", "w")
        if utils_file then
          utils_file:write([[
local M = {}

-- Terminal instances
M.terminals = {
  lazygit = nil,
  python = nil,
  nodejs = nil,
}

-- LazyGit toggle function
function M.toggle_lazygit()
  local Terminal = require("toggleterm.terminal").Terminal
  if not M.terminals.lazygit then
    M.terminals.lazygit = Terminal:new({
      cmd = "lazygit",
      dir = "git_dir",
      direction = "float",
      float_opts = {
        border = "curved",
      },
      on_open = function(term)
        vim.cmd("startinsert!")
        vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = term.bufnr })
      end,
      on_close = function()
        -- Refresh git status when lazygit closes
        vim.cmd("checktime")
        if package.loaded["gitsigns"] then
          vim.cmd("Gitsigns refresh")
        end
      end,
    })
  end
  M.terminals.lazygit:toggle()
end

-- Python REPL toggle function
function M.toggle_python()
  local Terminal = require("toggleterm.terminal").Terminal
  if not M.terminals.python then
    M.terminals.python = Terminal:new({
      cmd = "python",
      direction = "float",
      float_opts = {
        border = "curved",
      },
      on_open = function(term)
        vim.cmd("startinsert!")
      end,
    })
  end
  M.terminals.python:toggle()
end

-- Node.js REPL toggle function
function M.toggle_nodejs()
  local Terminal = require("toggleterm.terminal").Terminal
  if not M.terminals.nodejs then
    M.terminals.nodejs = Terminal:new({
      cmd = "node",
      direction = "float",
      float_opts = {
        border = "curved",
      },
      on_open = function(term)
        vim.cmd("startinsert!")
      end,
    })
  end
  M.terminals.nodejs:toggle()
end

return M
]])
          utils_file:close()
        end
      end

      -- Terminal-specific keymaps
      function _G.set_terminal_keymaps()
        local opts = { buffer = 0 }
        vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
        vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], opts)
        vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], opts)
        vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], opts)
        vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], opts)
      end

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          _G.set_terminal_keymaps()
        end,
      })
    end,
  },
}
