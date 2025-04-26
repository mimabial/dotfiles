-- Dashboard configuration
-- Sets up a welcome screen for Neovim

return {
  -- Dashboard: welcome screen
  {
    "glepnir/dashboard-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local dashboard = require("dashboard")

      -- Configure header
      local header = {
        "",
        "",
        " ███╗   ██╗███████╗ ██████╗  ██████╗ ██████╗ ██████╗ ███████╗ ",
        " ████╗  ██║██╔════╝██╔═══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝ ",
        " ██╔██╗ ██║█████╗  ██║   ██║██║     ██║   ██║██║  ██║█████╗   ",
        " ██║╚██╗██║██╔══╝  ██║   ██║██║     ██║   ██║██║  ██║██╔══╝   ",
        " ██║ ╚████║███████╗╚██████╔╝╚██████╗╚██████╔╝██████╔╝███████╗ ",
        " ╚═╝  ╚═══╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝ ",
        "",
        "                    [ Enhanced Neovim Setup ]                  ",
        "",
      }

      -- Configure menu
      local menu = {
        dashboard.button("f", " " .. "Find file", ":Telescope find_files <CR>"),
        dashboard.button("r", " " .. "Recent files", ":Telescope oldfiles <CR>"),
        dashboard.button("g", " " .. "Find text", ":Telescope live_grep <CR>"),
        dashboard.button("p", " " .. "Open project", ":Telescope projects <CR>"),
        dashboard.button("c", " " .. "Configuration", ":e $MYVIMRC <CR>"),
        dashboard.button("u", " " .. "Update plugins", ":Lazy sync<CR>"),
        dashboard.button("q", " " .. "Quit", ":qa<CR>"),
      }

      -- Configure dashboard
      dashboard.setup({
        theme = "hyper",
        shortcut_type = "letter",
        config = {
          header = header,
          shortcut = menu,
          packages = { enable = true }, -- Show plugin stats
          project = { enable = true, limit = 8 }, -- Show recent projects
          mru = { limit = 10 }, -- Show recent files
          footer = {}, -- Empty footer
        },
      })

      -- Disable statusline, tabline, and winbar on dashboard
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dashboard",
        callback = function()
          vim.opt_local.laststatus = 0
          vim.opt_local.showtabline = 0
          vim.opt_local.winbar = nil

          -- Exit dashboard when leaving
          vim.api.nvim_create_autocmd("BufLeave", {
            buffer = 0,
            callback = function()
              vim.opt.laststatus = 3
              vim.opt.showtabline = 2
            end,
            once = true,
          })
        end,
      })
    end,
  },
}
