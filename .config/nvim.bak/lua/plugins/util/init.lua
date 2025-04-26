-- Utility Plugins Loader
-- This file loads and configures utility plugins like Telescope, Treesitter, etc.

return {
  -- Import specific utility plugins
  require("plugins.util.telescope"),
  require("plugins.util.treesitter"),
  
  -- Common utilities
  {
    "nvim-lua/plenary.nvim",
    lazy = true,
  },
  
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },
  
  -- Which-key for keybinding help
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require("which-key").setup({
        plugins = {
          marks = true,
          registers = true,
          spelling = {
            enabled = true,
            suggestions = 20,
          },
        },
        window = {
          border = "single",
          padding = { 1, 1, 1, 1 },
        },
        layout = {
          height = { min = 4, max = 25 },
          width = { min = 20, max = 50 },
          spacing = 3,
        },
        show_help = true,
        show_keys = true,
      })
      
      -- Register which-key groups
      local wk = require("which-key")
      wk.register({
        ["<leader>f"] = { name = "+file" },
        ["<leader>b"] = { name = "+buffer" },
        ["<leader>c"] = { name = "+code" },
        ["<leader>g"] = { name = "+git" },
        ["<leader>t"] = { name = "+terminal/test" },
        ["<leader>d"] = { name = "+debug" },
        ["<leader>l"] = { name = "+lsp" },
        ["<leader>s"] = { name = "+search" },
        ["<leader>u"] = { name = "+ui" },
        ["<leader>w"] = { name = "+window" },
        ["<leader>a"] = { name = "+ai" },
        ["<leader>x"] = { name = "+diagnostics" },
      })
    end,
  },
  
  -- Better notifications
  {
    "rcarriga/nvim-notify",
    event = "VeryLazy",
    config = function()
      local notify = require("notify")
      notify.setup({
        stages = "fade",
        timeout = 3000,
        render = "default",
        background_colour = "#000000",
        max_width = 80,
      })
      
      vim.notify = notify
    end,
  },
  
  -- Improved UI components
  {
    "stevearc/dressing.nvim",
    event = "VeryLazy",
    config = function()
      require("dressing").setup({
        input = {
          enabled = true,
          default_prompt = "Input:",
          prompt_align = "left",
          insert_only = true,
          border = "rounded",
          relative = "cursor",
          prefer_width = 40,
          width = nil,
          max_width = { 140, 0.9 },
          min_width = { 20, 0.2 },
        },
        select = {
          enabled = true,
          backend = { "telescope", "fzf", "builtin" },
          trim_prompt = true,
          telescope = nil,
          builtin = {
            border = "rounded",
            relative = "editor",
            win_options = {
              winblend = 10,
            },
          },
        },
      })
    end,
  },
  
  -- Session management
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    config = function()
      require("persistence").setup({
        dir = vim.fn.expand(vim.fn.stdpath("state") .. "/sessions/"),
        options = { "buffers", "curdir", "tabpages", "winsize" },
        pre_save = nil,
      })
      
      -- Keymaps for session management
      vim.keymap.set("n", "<leader>qs", function() require("persistence").load() end, 
        { desc = "Restore last session" })
      vim.keymap.set("n", "<leader>ql", function() require("persistence").load({ last = true }) end, 
        { desc = "Restore last session" })
      vim.keymap.set("n", "<leader>qd", function() require("persistence").stop() end, 
        { desc = "Don't save current session" })
    end,
  },
}
