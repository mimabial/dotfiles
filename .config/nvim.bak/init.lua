--------------------------------------------------------------------------------
-- NeoCode - Advanced Neovim Configuration
-- Author: Your Name
-- License: MIT
-- Repository: https://github.com/yourusername/neocode
--------------------------------------------------------------------------------
--
-- This is the main entry point for the NeoCode configuration.
-- It bootstraps the configuration and lazy.nvim plugin manager.
--
-- Structure:
-- 1. Set leader keys early
-- 2. Bootstrap lazy.nvim if not already installed
-- 3. Load core modules (options, keymaps, autocmds)
-- 4. Initialize plugin system

-- Set leader keys before anything else to avoid mappings using the wrong leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

--------------------------------------------------------------------------------
-- Bootstrap package manager (lazy.nvim)
--------------------------------------------------------------------------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  -- Auto-install lazy.nvim if not present
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  print("Installed lazy.nvim!")
end
vim.opt.rtp:prepend(lazypath)

--------------------------------------------------------------------------------
-- Load core modules
--------------------------------------------------------------------------------

-- These modules set up fundamental Neovim settings and behaviors
require("core.options") -- Global Neovim options
require("core.keymaps") -- Global keymappings
require("core.autocmds") -- Autocommands
-- Core utility functions are available but only loaded when needed
-- require("core.utils")

--------------------------------------------------------------------------------
-- Initialize plugin system
--------------------------------------------------------------------------------

-- This loads all plugins and their configurations from lua/plugins/
require("lazy").setup({
  -- Load all plugin specifications from the plugins directory
  spec = {
    -- Include all .lua files from the plugins directory
    { import = "plugins" },

    -- Load user settings last to allow overriding defaults
    { import = "config.settings" },
  },

  -- UI configuration for lazy.nvim
  ui = {
    border = "rounded", -- Display borders on lazy.nvim windows
    icons = {
      cmd = "⌘",
      config = "🛠",
      event = "📅",
      ft = "📂",
      init = "⚙",
      keys = "🔑",
      plugin = "🔌",
      runtime = "💻",
      require = "🔍",
      source = "📄",
      start = "🚀",
      task = "📌",
      lazy = "💤 ",
    },
  },

  -- Install options
  install = {
    -- Try these colorschemes when starting for the first time
    colorscheme = { "tokyonight", "catppuccin", "habamax" },
    -- Don't install until :w (we'll install right away)
    missing = true,
  },

  -- Performance settings
  performance = {
    rtp = {
      -- Disable some built-in Neovim plugins that we don't need
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },

  -- Lazy can automatically check for plugin updates
  checker = {
    enabled = true, -- Auto-check for updates
    notify = false, -- Don't show notifications for updates
    frequency = 86400, -- Check once per day
  },

  -- Auto-reload configuration when changes are detected
  change_detection = {
    enabled = true,
    notify = false, -- Don't show notifications for config changes
  },
})

-- Print a welcome message when Neovim starts
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  callback = function()
    vim.notify("NeoCode is ready! 🚀", vim.log.levels.INFO)
  end,
})
