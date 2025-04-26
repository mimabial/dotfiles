-- Notifications configuration
-- Sets up a non-intrusive notification system

return {
  -- Noice: enhanced UI for messages, cmdline, and popupmenu
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    config = function()
      require("noice").setup({
        lsp = {
          -- Override markdown rendering so that cmp and other plugins use Treesitter
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
          },
          -- Show LSP progress as messages
          progress = {
            enabled = true,
            format = "lsp_progress",
            format_done = "lsp_progress_done",
            throttle = 1000 / 30, -- 30fps
          },
          -- Show LSP signature help in a floating window
          signature = {
            enabled = true,
            auto_open = {
              enabled = true,
              trigger = true,
              luasnip = true,
              throttle = 50,
            },
          },
          -- Enable hover documentation
          hover = {
            enabled = true,
          },
        },
        -- Configure cmdline UI
        cmdline = {
          enabled = true,
          view = "cmdline_popup",
          format = {
            cmdline = { pattern = "^:", icon = "", lang = "vim" },
            search_down = { kind = "search", pattern = "^/", icon = "🔍", lang = "regex" },
            search_up = { kind = "search", pattern = "^%?", icon = "🔍", lang = "regex" },
            filter = { pattern = "^:%s*!", icon = "$", lang = "bash" },
            lua = { pattern = "^:%s*lua%s+", icon = "", lang = "lua" },
            help = { pattern = "^:%s*he?l?p?%s+", icon = "❓" },
          },
        },
        -- Configure message UI
        messages = {
          enabled = true,
          view = "notify",
          view_error = "notify",
          view_warn = "notify",
          view_history = "messages",
          view_search = "virtualtext",
        },
        -- Configure popup menus
        popupmenu = {
          enabled = true,
          backend = "nui",
          kind_icons = {},
        },
        -- Configure notification routes
        routes = {
          {
            filter = { event = "msg_show", kind = { "", "echo", "echomsg" } },
            opts = { skip = true },
          },
          {
            filter = { event = "msg_show", find = "written" },
            opts = { view = "mini" },
          },
        },
        -- Enable command history
        history = {
          view = "split",
          opts = { enter = true, format = "details" },
        },
        -- Hide health status messages
        health = {
          checker = false,
        },
      })

      -- Configure nvim-notify
      require("notify").setup({
        background_colour = "#000000",
        fps = 60,
        level = 2,
        minimum_width = 50,
        render = "default",
        stages = "fade",
        timeout = 3000,
      })
    end,
    keys = {
      {
        "<leader>n",
        function()
          require("noice").cmd("dismiss")
        end,
        desc = "Dismiss notifications",
      },
      {
        "<leader>nl",
        function()
          require("noice").cmd("last")
        end,
        desc = "Last notification",
      },
      {
        "<leader>nh",
        function()
          require("noice").cmd("history")
        end,
        desc = "Notification history",
      },
    },
  },
}
