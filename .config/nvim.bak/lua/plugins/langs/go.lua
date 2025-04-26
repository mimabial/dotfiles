-- Go language configuration
-- Sets up Go development environment

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      if type(opts.servers) ~= "table" then
        opts.servers = {}
      end

      -- Configure gopls
      opts.servers.gopls = {
        settings = {
          gopls = {
            analyses = {
              unusedparams = true,
              shadow = true,
              unusedwrite = true,
              useany = true,
              nilness = true,
              ST1003 = true, -- check for naming conventions
            },
            experimentalPostfixCompletions = true,
            gofumpt = true,
            staticcheck = true,
            usePlaceholders = true,
            completeUnimported = true,
            directoryFilters = { "-.git", "-node_modules" },
            semanticTokens = true,
            codelenses = {
              gc_details = true,
              regenerate_cgo = true,
              run_govulncheck = true,
              test = true,
              tidy = true,
              upgrade_dependency = true,
              vendor = true,
            },
            hints = {
              assignVariableTypes = true,
              compositeLiteralFields = true,
              compositeLiteralTypes = true,
              constantValues = true,
              functionTypeParameters = true,
              parameterNames = true,
              rangeVariableTypes = true,
            },
          },
        },
      }

      -- Configure golangci_lint_ls
      opts.servers.golangci_lint_ls = {}
    end,
  },

  -- Go-specific plugins
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
    },
    event = { "CmdlineEnter", "VeryLazy" },
    ft = { "go", "gomod", "gosum", "gotmpl", "gohtmltmpl", "gotexttmpl" },
    build = ':lua require("go.install").update_all_sync()', -- Install/update binaries
    config = function()
      require("go").setup({
        -- gopls config
        lsp_cfg = false, -- handled in lspconfig
        -- goimports config
        goimports = "gopls", -- Use gopls for imports
        -- formatting
        formatter = "goimports",
        format_on_save = {
          enabled = true,
          async = false,
          -- Configure command to run on format
          command = function()
            return "gopls"
          end,
        },
        -- test configurations
        test_flags = { "-v" },
        test_runner = "go", -- Use standard go test
        run_in_floaterm = true, -- Run in float window
        -- lsp diagnostic config
        diagnostic = {
          underline = true,
          virtual_text = { spacing = 4, prefix = "●" },
          update_in_insert = false,
        },
        -- lsp inlay hints
        lsp_inlay_hints = {
          enable = true,
          parameter_hints_prefix = "← ",
          other_hints_prefix = "=> ",
        },
        -- lsp keybindings
        lsp_keymaps = false, -- Use our own keymap
        lsp_document_formatting = false,
        -- gopls configuration
        gopls_cmd = nil, -- Use lspconfig
        -- DAP config
        dap_debug = true,
        dap_debug_keymap = false, -- Use our own keymap
        dap_debug_gui = true,
        dap_debug_vt = true,
        -- Path to debug adapter
        dap_port = 38697,
        dap_timeout = 15,
        -- Build tags
        build_tags = "",
        -- Environment variables for running tests/debug
        textobjects = true,
        -- Go doc border style
        doc_popup_border = "rounded",
        -- Test result summary window border style
        test_popup_border = "rounded",
        -- Test popup configuration
        test_popup_width = 80,
        test_popup_height = 10,
        -- Verbose test output
        verbose_tests = true,
        -- Trouble integration
        trouble = true,
        -- Auto format imports
        gofmt = "gofumpt",
      })

      -- Set up Go-specific keymaps
      local wk = require("which-key")
      wk.register({
        g = {
          name = "Go",
          r = { "<cmd>GoRun<CR>", "Run" },
          t = { "<cmd>GoTest<CR>", "Test" },
          T = { "<cmd>GoTestFunc<CR>", "Test Function" },
          c = { "<cmd>GoCoverage<CR>", "Coverage" },
          a = { "<cmd>GoAlt<CR>", "Alt File" },
          i = { "<cmd>GoImport<CR>", "Import" },
          I = { "<cmd>GoInstall<CR>", "Install" },
          d = { "<cmd>GoDoc<CR>", "Doc" },
          f = { "<cmd>GoFillStruct<CR>", "Fill Struct" },
          e = { "<cmd>GoIfErr<CR>", "If Err" },
        },
      }, { prefix = "<leader>" })
    end,
  },

  -- Additional go tools
  {
    "olexsmir/gopher.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    ft = { "go", "gomod", "gosum", "gotmpl" },
    keys = {
      { "<leader>gsj", "<cmd>GoTagAdd json<CR>", desc = "Add JSON Tags" },
      { "<leader>gsy", "<cmd>GoTagAdd yaml<CR>", desc = "Add YAML Tags" },
      { "<leader>gsb", "<cmd>GoTagAdd bson<CR>", desc = "Add BSON Tags" },
      { "<leader>gsd", "<cmd>GoTagRm<CR>", desc = "Remove Tags" },
      { "<leader>ge", "<cmd>GoGenerate<CR>", desc = "Go Generate" },
      { "<leader>gim", "<cmd>GoImpl<CR>", desc = "Implement Interface" },
      { "<leader>gie", "<cmd>GoIfErr<CR>", desc = "Add If Err" },
    },
    config = function(_, opts)
      require("gopher").setup(opts)
    end,
    build = function()
      vim.cmd([[ silent! GoInstallDeps ]])
    end,
  },
}
