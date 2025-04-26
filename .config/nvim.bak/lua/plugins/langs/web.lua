--------------------------------------------------------------------------------
-- Web Development Configuration
--------------------------------------------------------------------------------
--
-- This module provides comprehensive support for web development:
--
-- Features:
-- 1. JavaScript/TypeScript with full LSP support
-- 2. HTML, CSS, JSON with schema validation
-- 3. Framework support (React, Vue, Angular, Svelte)
-- 4. Tailwind CSS integration
-- 5. EmmetLS for HTML/CSS expansion
-- 6. ESLint and Prettier integration
-- 7. Testing frameworks (Jest, Vitest, etc.)
-- 8. Package management (npm, yarn, pnpm)
--
-- Language servers included:
-- - tsserver: TypeScript/JavaScript
-- - eslint: Linting
-- - volar: Vue
-- - astro: Astro framework
-- - tailwindcss: Tailwind CSS
-- - cssls: CSS
-- - html: HTML
-- - jsonls: JSON with schema
-- - emmet_ls: Emmet
--------------------------------------------------------------------------------

return {
  -- TypeScript/JavaScript language support
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- TypeScript/JavaScript server
        tsserver = {
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = "all",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints = "all",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
            completions = {
              completeFunctionCalls = true,
            },
          },
        },

        -- ESLint integration
        eslint = {
          settings = {
            packageManager = "npm",
            experimental = {
              useFlatConfig = false,
            },
            workingDirectories = { { mode = "auto" } },
            validate = "on",
            format = { enable = true },
            quiet = false,
            onIgnoredFiles = "off",
            rulesCustomizations = {},
            run = "onType",
            problems = {
              shortenToSingleLine = false,
            },
            -- Use .eslintignore file from project
            useESLintClass = false,
            codeAction = {
              disableRuleComment = {
                enable = true,
                location = "separateLine",
              },
              showDocumentation = {
                enable = true,
              },
            },
          },
        },

        -- HTML language server
        html = {
          filetypes = { "html", "htmldjango", "handlebars", "hbs", "ejs" },
          settings = {
            html = {
              format = {
                templating = true,
                wrapLineLength = 120,
                wrapAttributes = "auto",
              },
              hover = {
                documentation = true,
                references = true,
              },
            },
          },
        },

        -- CSS language server
        cssls = {
          settings = {
            css = {
              validate = true,
              lint = {
                unknownAtRules = "ignore", -- Ignore unknown at-rules for framework compatibility
              },
            },
            scss = {
              validate = true,
              lint = {
                unknownAtRules = "ignore",
              },
            },
            less = {
              validate = true,
              lint = {
                unknownAtRules = "ignore",
              },
            },
          },
        },

        -- JSON with schema validation
        jsonls = {
          settings = {
            json = {
              schemas = require("schemastore").json.schemas(),
              validate = { enable = true },
            },
          },
        },

        -- Vue language server
        volar = {
          filetypes = { "vue", "typescript", "javascript" },
        },

        -- Tailwind CSS support
        tailwindcss = {
          filetypes = {
            "html",
            "css",
            "scss",
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
            "svelte",
          },
          settings = {
            tailwindCSS = {
              experimental = {
                classRegex = {
                  'class[:]\\s*"([^"]*)"',
                  'className[:]\\s*"([^"]*)"',
                  "class[:]\\s*'([^']*)'",
                  "className[:]\\s*'([^']*)'",
                  "tw`([^`]*)",
                  "tw\\.[^`]+`([^`]*)`",
                  "tw\\(.*?\\).*?`([^`]*)",
                },
              },
              includeLanguages = {
                typescript = "javascript",
                typescriptreact = "javascript",
                ["html-eex"] = "html",
                ["phoenix-heex"] = "html",
                heex = "html",
                svelte = "html",
                vue = "html",
                astro = "html",
              },
            },
          },
        },

        -- Emmet integration for HTML/CSS expansion
        emmet_ls = {
          filetypes = {
            "html",
            "css",
            "scss",
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
            "svelte",
            "astro",
          },
        },

        -- Astro framework support
        astro = {},

        -- Svelte framework support
        svelte = {},

        -- Angular framework support
        angularls = {},
      },
    },
  },

  -- TypeScript-specific tools
  {
    "pmizio/typescript-tools.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
    opts = {
      -- This plugin provides better TypeScript server functionality
      settings = {
        tsserver_file_preferences = {
          includeInlayParameterNameHints = "all",
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
        },
        tsserver_format_options = {
          allowIncompleteCompletions = false,
          allowRenameOfImportPath = false,
        },
        -- Complement with user preferences
        complete_function_calls = true,
        include_completions_with_insert_text = true,
        code_lens = "all",
      },
    },
  },

  -- Schema Store for JSON/YAML validation
  {
    "b0o/schemastore.nvim",
    version = false, -- last release is too old
  },

  -- HTML tag auto-closing and matching
  {
    "windwp/nvim-ts-autotag",
    opts = {
      enable_close_on_slash = true,
      filetypes = {
        "html",
        "xml",
        "javascript",
        "javascriptreact",
        "typescript",
        "typescriptreact",
        "vue",
        "svelte",
        "astro",
      },
    },
  },

  -- Tailwind CSS colorizer (show colors in completion)
  {
    "roobert/tailwindcss-colorizer-cmp.nvim",
    config = true,
  },

  -- Format & Lint with Prettier/ESLint
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { { "prettierd", "prettier" } },
        typescript = { { "prettierd", "prettier" } },
        javascriptreact = { { "prettierd", "prettier" } },
        typescriptreact = { { "prettierd", "prettier" } },
        svelte = { { "prettierd", "prettier" } },
        vue = { { "prettierd", "prettier" } },
        astro = { { "prettierd", "prettier" } },
        css = { { "prettierd", "prettier" } },
        scss = { { "prettierd", "prettier" } },
        less = { { "prettierd", "prettier" } },
        html = { { "prettierd", "prettier" } },
        json = { { "prettierd", "prettier" } },
        jsonc = { { "prettierd", "prettier" } },
        yaml = { { "prettierd", "prettier" } },
        markdown = { { "prettierd", "prettier" } },
        graphql = { { "prettierd", "prettier" } },
      },
    },
  },

  -- Linting
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        svelte = { "eslint_d" },
        vue = { "eslint_d" },
        css = { "stylelint" },
        scss = { "stylelint" },
      },
    },
  },

  -- Testing with Jest/Vitest
  {
    "nvim-neotest/neotest",
    dependencies = {
      "haydenmeade/neotest-jest",
      "marilari88/neotest-vitest",
    },
    opts = function(_, opts)
      vim.list_extend(opts.adapters or {}, {
        require("neotest-jest")({
          jestCommand = "npm test --",
          jestConfigFile = "jest.config.js",
          env = { CI = true },
          cwd = function()
            return vim.fn.getcwd()
          end,
        }),
        require("neotest-vitest"),
      })
    end,
  },

  -- React specific tools
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "jose-elias-alvarez/typescript.nvim",
    },
    opts = {
      servers = {
        -- React optimization for tsserver
        tsserver = {
          settings = {
            typescript = {
              suggest = {
                completeFunctionCalls = true,
                includeAutomaticOptionalChainCompletions = true,
                includeCompletionsForImportStatements = true,
              },
            },
          },
          on_attach = function(client, bufnr)
            -- Disable tsserver formatting in favor of prettier
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
          end,
        },
      },
    },
  },

  -- Node/NPM tools integration
  {
    "vuki656/package-info.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = { "BufRead package.json" },
    opts = {
      colors = {
        up_to_date = "#3C4048",
        outdated = "#d19a66",
      },
      icons = {
        enable = true,
        style = {
          up_to_date = "  ",
          outdated = "  ",
        },
      },
      autostart = true,
      hide_up_to_date = false,
      hide_unstable_versions = false,
      package_manager = "npm",
    },
    keys = {
      { "<leader>pn", "<cmd>lua require('package-info').change_version()<cr>", desc = "Change Package Version" },
      { "<leader>pi", "<cmd>lua require('package-info').install()<cr>", desc = "Install Package" },
      { "<leader>pd", "<cmd>lua require('package-info').delete()<cr>", desc = "Delete Package" },
      { "<leader>ps", "<cmd>lua require('package-info').show()<cr>", desc = "Show Package Info" },
      { "<leader>ph", "<cmd>lua require('package-info').hide()<cr>", desc = "Hide Package Info" },
      { "<leader>pt", "<cmd>lua require('package-info').toggle()<cr>", desc = "Toggle Package Info" },
      { "<leader>pu", "<cmd>lua require('package-info').update()<cr>", desc = "Update Package" },
    },
  },

  -- Add TreeSitter parsers for web languages
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "javascript",
        "typescript",
        "tsx",
        "html",
        "css",
        "scss",
        "json",
        "jsonc",
        "graphql",
        "vue",
        "svelte",
        "astro",
        "jsdoc",
        "comment",
        "regex",
      },
    },
  },
}
