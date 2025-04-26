--------------------------------------------------------------------------------
-- LSP (Language Server Protocol) Configuration
--------------------------------------------------------------------------------
--
-- This module configures Language Server Protocol integration which provides:
-- * Code completion
-- * Diagnostics (errors, warnings)
-- * Hover documentation
-- * Go-to-definition
-- * Symbol search
-- * Code actions
-- * Inlay hints
-- * And more...
--
-- The configuration is modular:
-- 1. LSP servers configuration (servers.lua)
-- 2. Formatting tools (formatters.lua)
-- 3. Linters (linters.lua)
-- 4. LSP-specific keymaps (keymaps.lua)
-- 5. LSP UI configuration (ui.lua)
--
-- We use the following components:
-- * nvim-lspconfig: Base LSP configuration
-- * mason.nvim: Install LSP servers, formatters, and linters
-- * mason-lspconfig.nvim: Bridge between mason and lspconfig
-- * none-ls.nvim: Non-LSP sources (formatters, linters)
-- * nvim-navic: Code context in winbar
-- * fidget.nvim: LSP progress indicator
-- * lsp_signature.nvim: Function signature help
--------------------------------------------------------------------------------

return {
  -- Main LSP configuration plugin
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      -- Automatically install LSP servers
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },

      -- LSP status indicator
      { "j-hui/fidget.nvim", opts = { notification = { window = { winblend = 0 } } } },

      -- Navigation and UI enhancements
      { "SmiteshP/nvim-navic" }, -- Code context
      { "folke/neodev.nvim" }, -- Better Lua development
      { "simrat39/symbols-outline.nvim" }, -- Symbol viewer
      { "ray-x/lsp_signature.nvim" }, -- Function signature help

      -- Schema and type support
      { "b0o/schemastore.nvim" }, -- JSON schema support

      -- Diagnostics and additional tooling
      { "nvimtools/none-ls.nvim" }, -- Non-LSP sources

      -- Required plugins
      "nvim-lua/plenary.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Load helper modules for LSP configuration
      local lspconfig = require("lspconfig")

      -- Import other LSP-related modules
      require("plugins.lsp.ui") -- LSP UI components
      local servers = require("plugins.lsp.servers") -- LSP server configurations
      local keymaps = require("plugins.lsp.keymaps") -- LSP keymaps

      -- Setup navic (code context in winbar)
      local navic = require("nvim-navic")
      navic.setup({
        icons = {
          File = " ",
          Module = " ",
          Namespace = " ",
          Package = " ",
          Class = " ",
          Method = " ",
          Property = " ",
          Field = " ",
          Constructor = " ",
          Enum = " ",
          Interface = " ",
          Function = " ",
          Variable = " ",
          Constant = " ",
          String = " ",
          Number = " ",
          Boolean = " ",
          Array = " ",
          Object = " ",
          Key = " ",
          Null = " ",
          EnumMember = " ",
          Struct = " ",
          Event = " ",
          Operator = " ",
          TypeParameter = " ",
        },
        highlight = true,
        separator = " > ",
        depth_limit = 0,
        depth_limit_indicator = "..",
      })

      -- Configure neodev for better Lua development
      require("neodev").setup({
        library = {
          enabled = true,
          runtime = true,
          types = true,
          plugins = true,
        },
        setup_jsonls = true,
        lspconfig = true,
      })

      -- Configure symbols outline (symbol browser)
      require("symbols-outline").setup({
        highlight_hovered_item = true,
        show_guides = true,
        auto_preview = false,
        position = "right",
        width = 25,
        auto_close = false,
        show_numbers = false,
        show_relative_numbers = false,
        show_symbol_details = true,
      })

      -- Setup LSP signature help
      require("lsp_signature").setup({
        bind = true,
        handler_opts = {
          border = "rounded",
        },
        hint_enable = true,
        hint_prefix = "🔍 ",
        hint_scheme = "String",
        hi_parameter = "Search",
        toggle_key = "<C-k>", -- Toggle signature on and off (in insert mode)
        select_signature_key = "<C-n>", -- Cycle between signatures
      })

      -- Define capabilities with nvim-cmp integration
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)
      capabilities.textDocument.completion.completionItem = {
        documentationFormat = { "markdown", "plaintext" },
        snippetSupport = true,
        preselectSupport = true,
        insertReplaceSupport = true,
        labelDetailsSupport = true,
        deprecatedSupport = true,
        commitCharactersSupport = true,
        tagSupport = { valueSet = { 1 } },
        resolveSupport = {
          properties = {
            "documentation",
            "detail",
            "additionalTextEdits",
          },
        },
      }

      -- Setup LSP handlers with rounded borders
      local handlers = {
        ["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" }),
        ["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" }),
      }

      -- Setup mason (LSP installer)
      require("mason").setup({
        ui = {
          border = "rounded",
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      })

      -- Setup mason-lspconfig (bridge between mason and lspconfig)
      require("mason-lspconfig").setup({
        ensure_installed = servers.ensure_installed,
        automatic_installation = true,
      })

      -- Common on_attach function for all LSP servers
      local function on_attach(client, bufnr)
        -- Apply keymaps for this buffer
        keymaps.on_attach(client, bufnr)

        -- Enable navic (code context) if the LSP supports document symbols
        if client.server_capabilities.documentSymbolProvider then
          navic.attach(client, bufnr)
        end

        -- Enable inlay hints if available (Neovim 0.10+)
        if vim.lsp.inlay_hint and client.server_capabilities.inlayHintProvider then
          vim.lsp.inlay_hint.enable(bufnr, true)
        end

        -- Set up LSP signature help for this buffer
        require("lsp_signature").on_attach({
          bind = true,
          use_lspsaga = false,
          floating_window = true,
          fix_pos = false,
          hint_enable = true,
          hi_parameter = "Search",
          handler_opts = {
            border = "rounded",
          },
        }, bufnr)
      end

      -- Setup each language server
      local setup_server = function(server_name)
        local server_opts = servers.settings[server_name] or {}

        -- Default options for all language servers
        server_opts.capabilities = capabilities
        server_opts.handlers = handlers

        -- Add common on_attach if not already set
        local user_on_attach = server_opts.on_attach
        server_opts.on_attach = function(client, bufnr)
          on_attach(client, bufnr)
          if user_on_attach then
            user_on_attach(client, bufnr)
          end
        end

        -- Configure the server
        lspconfig[server_name].setup(server_opts)
      end

      -- Setup each language server using mason-lspconfig
      require("mason-lspconfig").setup_handlers({
        function(server_name)
          setup_server(server_name)
        end,

        -- Custom handling for specific servers can be added here as needed
        -- Example:
        -- ["rust_analyzer"] = function()
        --   -- Custom setup for rust_analyzer
        -- end,
      })

      -- Setup null-ls (non-LSP sources like formatters and linters)
      local null_ls = require("none-ls")

      -- Load formatter and linter configurations
      local formatters = require("plugins.lsp.formatters")
      local linters = require("plugins.lsp.linters")

      null_ls.setup({
        debug = false,
        sources = vim.list_extend(formatters.sources, linters.sources),
        on_attach = on_attach,
      })

      -- Setup autoformatting on save if enabled
      vim.api.nvim_create_autocmd("BufWritePre", {
        callback = function()
          -- Check for autoformat disabling comment or global setting
          local bufnr = vim.api.nvim_get_current_buf()
          local disable_autoformat = vim.b[bufnr].disable_autoformat or false

          if not disable_autoformat then
            -- Format using LSP or null-ls
            vim.lsp.buf.format({
              async = false,
              timeout_ms = 5000,
            })
          end
        end,
      })

      -- Create commands to toggle autoformatting
      vim.api.nvim_create_user_command("FormatToggle", function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].disable_autoformat = not vim.b[bufnr].disable_autoformat
        local status = vim.b[bufnr].disable_autoformat and "disabled" or "enabled"
        vim.notify("Autoformatting " .. status .. " for this buffer", vim.log.levels.INFO)
      end, {})

      vim.api.nvim_create_user_command("FormatEnable", function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].disable_autoformat = false
        vim.notify("Autoformatting enabled for this buffer", vim.log.levels.INFO)
      end, {})

      vim.api.nvim_create_user_command("FormatDisable", function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].disable_autoformat = true
        vim.notify("Autoformatting disabled for this buffer", vim.log.levels.INFO)
      end, {})
    end,
  },

  -- Mason for installing LSP servers, formatters, linters, and DAP
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    keys = { { "<leader>lm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts = {
      ensure_installed = {
        -- Core formatters and linters for common languages
        "stylua", -- Lua
        "shfmt", -- Shell
        "shellcheck", -- Shell
        "black", -- Python
        "isort", -- Python
        "flake8", -- Python
        "prettier", -- Web
        "eslint_d", -- JavaScript/TypeScript
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)

      -- Ensure the specified tools are installed
      local mr = require("mason-registry")
      local function ensure_installed()
        for _, tool in ipairs(opts.ensure_installed) do
          local p = mr.get_package(tool)
          if not p:is_installed() then
            p:install()
          end
        end
      end

      -- Auto-install if mason registry is available
      if mr.refresh then
        mr.refresh(ensure_installed)
      else
        ensure_installed()
      end
    end,
  },
}
