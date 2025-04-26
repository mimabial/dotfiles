-- Plugin manager initialization
-- This file is responsible for setting up the plugin manager and loading plugins

-- Bootstrap lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Set leader key before lazy setup
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Plugin specification
return require("lazy").setup({
  -- Load plugin categories
  { import = "plugins.ui" }, -- UI enhancements
  { import = "plugins.editor" }, -- Editor features
  { import = "plugins.coding" }, -- Coding assistance
  { import = "plugins.lsp" }, -- Language server configurations
  { import = "plugins.tools" }, -- Development tools
  { import = "plugins.util" }, -- Utility plugins
  { import = "plugins.langs" }, -- Language-specific configurations
}, {
  -- Lazy.nvim options
  install = {
    colorscheme = { "tokyonight" }, -- Default colorscheme during installation
  },
  checker = {
    enabled = true, -- Check for plugin updates
    frequency = 86400, -- Check once a day
    notify = false, -- Don't show update notifications
  },
  change_detection = {
    enabled = true, -- Auto-reload configuration on changes
    notify = false, -- Don't show change notifications
  },
  performance = {
    cache = {
      enabled = true, -- Enable caching for better performance
    },
    reset_packpath = true, -- Reset packpath for better plugin isolation
    rtp = {
      disabled_plugins = { -- Disable unused Neovim plugins for better startup
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded", -- UI elements border style
    icons = {
      cmd = "⌘",
      config = "🛠",
      event = "📅",
      ft = "📂",
      init = "⚙",
      keys = "🔑",
      plugin = "🔌",
      runtime = "🏃",
      source = "📄",
      start = "🚀",
      task = "📌",
    },
  },
})
