  -- Highly experimental plugin that completely replaces the UI for messages, cmdline and the popupmenu.
return  {
    -- dir = "~/personal/noice.nvim",
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      "MunifTanjim/nui.nvim",
      -- OPTIONAL:
      --   `nvim-notify` is only needed, if you want to use the notification view.
      --   If not available, we use `mini` as the fallback
      "rcarriga/nvim-notify",
    },
    opts = {
      views = {
        hover = {
          border = {
            style = "rounded",
            padding = { 0, 1 },
          },
          size = {
            max_width = 80,
          },
          position = { row = 2, col = 2 },
        },
      },
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
        hover = {
          -- view = "split",
        },
      },
      routes = {
        {
          filter = {
            any = {
              { find = "No information available" },
            },
          },
          skip = true,
        },
        {
          filter = {
            event = "msg_show",
            any = {
              { find = "%d+L, %d+B" },
              { find = "; after #%d+" },
              { find = "; before #%d+" },
              { find = "%d+ fewer lines" },
            },
          },
          view = "mini",
        },
      },
      presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = false, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
      cmdline = {
        enabled = true,
        view = "cmdline",
      },
      messages = {
        enabled = true,
        view = "mini",
        view_warn = "mini",
        view_error = "mini",
        -- view_history = "messages",
        -- view = "notify",
        -- view_error = "messages", -- view for errors
        -- view_warn = "messages", -- view for warnings
        -- view_history = "messages", -- view for :messages
        -- view_search = "virtualtext", -- view for search count messages. Set to `false` to disable
      },
      -- popupmenu = {
      --   enabled = false,
      -- },
      notify = {
        enabled = true,
        view = "mini",
      },
      --
      commands = {
        all = {
          view = "split",
          opts = { enter = true, format = "details" },
          filter = {},
        },
      },
    },
    -- stylua: ignore
    keys = {
      { "<F7>", [[<cmd>NoiceDismiss<cr>]], desc = "Dismiss all Notifications", },
      {
        "<S-Enter>",
        function() require("noice").redirect(vim.fn.getcmdline()) end,
        mode = "c",
        desc = "Redirect Cmdline"
      },
      { "<leader>nn", function() require("noice").cmd("last") end,    desc = "Noice Last Message" },
      { "<leader>nl", function() require("noice").cmd("history") end, desc = "Noice History" },
      { "<leader>na", function() require("noice").cmd("all") end,     desc = "Noice All" },
      { "<leader>nm", [[<cmd>messages<cr>]],                          desc = "messages" },
      { "<leader>nd", function() require("noice").cmd("dismiss") end, desc = "Dismiss All" },
      {
        "<c-f>",
        function() if not require("noice.lsp").scroll(4) then return "<c-f>" end end,
        silent = true,
        expr = true,
        desc = "Scroll forward",
        mode = { "i", "n", "s" }
      },
      {
        "<c-b>",
        function() if not require("noice.lsp").scroll(-4) then return "<c-b>" end end,
        silent = true,
        expr = true,
        desc = "Scroll backward",
        mode = { "i", "n", "s" }
      },
    },
    config = function(_, opts)
      require("noice").setup(opts)
      vim.api.nvim_set_hl(0, "LspSignatureActiveParameter", { link = "@type.builtin", default = true })
      vim.api.nvim_set_hl(0, "NoiceVirtualText", { fg = "#c8d3f5", bg = "#3e68d7", italic = true })
    end,
  },