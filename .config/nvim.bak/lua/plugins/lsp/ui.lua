-- LSP UI configuration
-- Sets up UI elements for LSP features

return {
  -- LSP UI improvements
  {
    "nvimdev/lspsaga.nvim",
    event = "LspAttach",
    opts = {
      ui = {
        border = "rounded",
        title = true,
        winblend = 0,
        expand = "",
        collapse = "",
        code_action = "💡",
        diagnostic = "🔍",
        incoming = " ",
        outgoing = " ",
        hover = " ",
        kind = {
          -- Kind icons used in Lspsaga
          -- Matches the kind icons in Mason
        },
      },
      hover = {
        max_width = 0.6,
        max_height = 0.6,
        open_link = "gx",
        open_browser = nil,
      },
      diagnostic = {
        on_insert = false,
        on_insert_follow = false,
        insert_winblend = 0,
        show_virt_line = true,
        show_code_action = true,
        show_source = true,
        jump_num_shortcut = true,
        max_width = 0.7,
        max_height = 0.6,
        max_show_width = 0.7,
        max_show_height = 0.6,
        text_hl_follow = true,
        border_follow = true,
        keys = {
          exec_action = "<CR>",
          quit = { "q", "<ESC>" },
          go_action = "g",
        },
      },
      code_action = {
        num_shortcut = true,
        show_server_name = true,
        keys = {
          quit = { "q", "<ESC>" },
          exec = "<CR>",
        },
      },
      lightbulb = {
        enable = true,
        enable_in_insert = true,
        sign = true,
        sign_priority = 40,
        virtual_text = true,
      },
      preview = {
        lines_above = 0,
        lines_below = 10,
      },
      scroll_preview = {
        scroll_down = "<C-d>",
        scroll_up = "<C-u>",
      },
      symbol_in_winbar = {
        enable = true,
        separator = " › ",
        hide_keyword = true,
        show_file = true,
        click_support = false,
      },
    },
    keys = {
      { "<leader>ca", "<cmd>Lspsaga code_action<CR>", desc = "Code Action", mode = { "n", "v" } },
      { "<leader>cr", "<cmd>Lspsaga rename<CR>", desc = "Rename" },
      { "<leader>cR", "<cmd>Lspsaga rename ++project<CR>", desc = "Rename in Project" },
      { "gd", "<cmd>Lspsaga peek_definition<CR>", desc = "Peek Definition" },
      { "gD", "<cmd>Lspsaga goto_definition<CR>", desc = "Go to Definition" },
      { "gt", "<cmd>Lspsaga peek_type_definition<CR>", desc = "Peek Type" },
      { "gT", "<cmd>Lspsaga goto_type_definition<CR>", desc = "Go to Type Definition" },
      { "K", "<cmd>Lspsaga hover_doc<CR>", desc = "Hover Documentation" },
      { "<leader>cl", "<cmd>Lspsaga show_line_diagnostics<CR>", desc = "Line Diagnostics" },
      { "<leader>cb", "<cmd>Lspsaga show_buf_diagnostics<CR>", desc = "Buffer Diagnostics" },
      { "<leader>co", "<cmd>Lspsaga outline<CR>", desc = "Code Outline" },
      { "<leader>ci", "<cmd>Lspsaga incoming_calls<CR>", desc = "Incoming Calls" },
      { "<leader>co", "<cmd>Lspsaga outgoing_calls<CR>", desc = "Outgoing Calls" },
      { "[d", "<cmd>Lspsaga diagnostic_jump_prev<CR>", desc = "Previous Diagnostic" },
      { "]d", "<cmd>Lspsaga diagnostic_jump_next<CR>", desc = "Next Diagnostic" },
      {
        "[e",
        function()
          require("lspsaga.diagnostic"):goto_prev({ severity = vim.diagnostic.severity.ERROR })
        end,
        desc = "Previous Error",
      },
      {
        "]e",
        function()
          require("lspsaga.diagnostic"):goto_next({ severity = vim.diagnostic.severity.ERROR })
        end,
        desc = "Next Error",
      },
    },
  },

  -- LSP diagnostics panel
  {
    "folke/trouble.nvim",
    cmd = { "Trouble", "TroubleToggle", "TroubleRefresh" },
    opts = {
      position = "bottom",
      height = 15,
      icons = true,
      mode = "workspace_diagnostics",
      fold_open = "",
      fold_closed = "",
      indent_lines = false,
      signs = {
        error = "",
        warning = "",
        hint = "",
        information = "",
        other = "",
      },
      action_keys = {
        close = "q",
        cancel = "<esc>",
        refresh = "r",
        jump = { "<cr>", "<tab>" },
        open_split = { "<c-x>" },
        open_vsplit = { "<c-v>" },
        open_tab = { "<c-t>" },
        jump_close = { "o" },
        toggle_mode = "m",
        toggle_preview = "P",
        hover = "K",
        preview = "p",
        close_folds = { "zM", "zm" },
        open_folds = { "zR", "zr" },
        toggle_fold = { "zA", "za" },
        previous = "k",
        next = "j",
      },
      win = {
        border = "rounded",
      },
      auto_open = false,
      auto_close = false,
      auto_preview = true,
      auto_fold = false,
      auto_jump = { "lsp_definitions" },
      signs = {
        error = "",
        warning = "",
        hint = "",
        information = "",
        other = "﫠",
      },
      use_diagnostic_signs = false,
    },
    keys = {
      { "<leader>xx", "<cmd>TroubleToggle<CR>", desc = "Toggle Trouble" },
      { "<leader>xw", "<cmd>TroubleToggle workspace_diagnostics<CR>", desc = "Workspace Diagnostics" },
      { "<leader>xd", "<cmd>TroubleToggle document_diagnostics<CR>", desc = "Document Diagnostics" },
      { "<leader>xl", "<cmd>TroubleToggle loclist<CR>", desc = "Location List" },
      { "<leader>xq", "<cmd>TroubleToggle quickfix<CR>", desc = "Quickfix List" },
      { "gR", "<cmd>TroubleToggle lsp_references<CR>", desc = "LSP References" },
    },
  },

  -- Custom UI tweaks
  {
    "nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    init = function()
      -- Better UI
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
        },
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
        },
      })

      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })

      vim.lsp.handlers["textDocument/signatureHelp"] =
        vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })

      -- Add icons to diagnostic signs
      local signs = { Error = " ", Warn = " ", Hint = "󰌵 ", Info = " " }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end
    end,
  },
}
