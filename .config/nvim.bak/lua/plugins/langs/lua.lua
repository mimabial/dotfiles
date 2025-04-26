--------------------------------------------------------------------------------
-- Lua Development Configuration
--------------------------------------------------------------------------------
--
-- This module provides comprehensive support for Lua development:
--
-- Features:
-- 1. lua-ls Language Server with Neovim API awareness
-- 2. Auto-formatting with StyLua
-- 3. Linting with Luacheck
-- 4. Syntax highlighting via Treesitter
-- 5. Documentation generation
-- 6. Enhanced completion with snippets
-- 7. Neovim-specific development tools
-- 8. Type annotations and hints
--
-- When editing Lua files, you get:
-- - Intelligent code completion with Neovim API docs
-- - Real-time error checking and linting
-- - Structure view with symbols outline
-- - Auto-formatting on save
--------------------------------------------------------------------------------

return {
  -- Lua LSP configuration
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- Neodev enhances lua_ls for Neovim Lua API development
      "folke/neodev.nvim",
    },
    opts = {
      servers = {
        lua_ls = {
          settings = {
            Lua = {
              runtime = {
                -- Tell the language server which version of Lua you're using
                version = "LuaJIT",
              },
              completion = {
                callSnippet = "Replace", -- Show function call snippets
                workspaceWord = true, -- Complete words from workspace
                showWord = "Disable", -- Don't include all words
              },
              diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = {
                  "vim",
                  "describe",
                  "it",
                  "before_each",
                  "after_each",
                  "teardown",
                  "pending",
                  "assert",
                },
                disable = {
                  "trailing-space", -- Let formatters handle this
                  "undefined-doc-name", -- Too many false positives
                },
                -- Adjust severity of certain diagnostics
                severity = {
                  ["unused-local"] = "Hint",
                  ["unused-vararg"] = "Hint",
                  ["lowercase-global"] = "Information",
                },
              },
              format = {
                enable = false, -- We use StyLua instead
              },
              hint = { -- Inlay hints (Neovim 0.10+)
                enable = true,
                setType = true,
                paramType = true,
                paramName = "Literal",
                arrayIndex = "Enable",
                semicolon = "SameLine",
              },
              workspace = {
                -- Make the server aware of Neovim runtime files
                library = {
                  vim.fn.expand("$VIMRUNTIME/lua"),
                  vim.fn.stdpath("config") .. "/lua",
                  "${3rd}/luv/library",
                },
                -- Don't check third-party modules
                checkThirdParty = false,
                -- Configure max preload files
                maxPreload = 2000,
                preloadFileSize = 50000,
              },
              -- Do not send telemetry data
              telemetry = {
                enable = false,
              },
            },
          },
        },
      },
    },
  },

  -- Enhance Lua development for Neovim configuration
  {
    "folke/neodev.nvim",
    opts = {
      library = {
        enabled = true,
        runtime = true,
        types = true,
        plugins = true,
      },
      setup_jsonls = true,
      lspconfig = true,
      pathStrict = true,
    },
  },

  -- Enhanced Lua REPL
  {
    "bfredl/nvim-luadev",
    ft = "lua",
    config = function()
      -- Set up Lua evaluation capabilities
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          -- Map keys to evaluate Lua code
          vim.keymap.set("n", "<leader>ll", "<Plug>(Luadev-RunLine)", { buffer = true, desc = "Evaluate Line" })
          vim.keymap.set("v", "<leader>le", "<Plug>(Luadev-Run)", { buffer = true, desc = "Evaluate Selection" })
          vim.keymap.set("n", "<leader>lr", "<Plug>(Luadev-RunWord)", { buffer = true, desc = "Evaluate Word" })
          vim.keymap.set("n", "<leader>lc", "<cmd>Luadev<CR>", { buffer = true, desc = "Open REPL" })
        end,
      })
    end,
  },

  -- Configure formatter for Lua
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
      },
      formatters = {
        stylua = {
          -- Use .stylua.toml or stylua.toml from the project
          -- if found, otherwise use default config
          args = {
            "--search-parent-directories",
            "--stdin-filepath",
            "$FILENAME",
            "-",
          },
        },
      },
    },
  },

  -- Configure linter for Lua
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        lua = { "luacheck" },
      },
      linters = {
        luacheck = {
          args = {
            "--globals",
            "vim",
            "--no-max-line-length",
            "-",
          },
        },
      },
    },
  },

  -- Lua documentation generator
  {
    "danymat/neogen",
    opts = {
      languages = {
        lua = {
          template = {
            annotation_convention = "emmylua",
          },
        },
      },
    },
    config = function(_, opts)
      require("neogen").setup(opts)

      -- Add Lua-specific keymaps for documentation
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          vim.keymap.set("n", "<leader>cd", function()
            require("neogen").generate({ type = "func" })
          end, { buffer = true, desc = "Generate Function Doc" })

          vim.keymap.set("n", "<leader>cD", function()
            require("neogen").generate({ type = "file" })
          end, { buffer = true, desc = "Generate File Doc" })
        end,
      })
    end,
  },

  -- Add TreeSitter support for Lua
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua",
        "luadoc", -- For LuaDoc/EmmyLua comments
        "query", -- For TreeSitter queries
      },
    },
  },

  -- Lua testing integration
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-plenary",
    },
    opts = function(_, opts)
      vim.list_extend(opts.adapters or {}, {
        require("neotest-plenary"),
      })
    end,
  },

  -- Helper for developing plugins
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        -- Add libraries for specific plugins or modules
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        { path = "lazy.nvim", words = { "lazy" } },
      },
    },
  },

  -- Snippets for Lua
  {
    "L3MON4D3/LuaSnip",
    config = function()
      require("luasnip").filetype_extend("lua", {
        -- Extend with Lua-specific snippets
        -- These come from friendly-snippets
        "luadoc", -- Documentation snippets
        "neovim", -- Neovim-specific snippets
      })

      -- Add custom snippets for Lua
      local ls = require("luasnip")
      local s = ls.snippet
      local t = ls.text_node
      local i = ls.insert_node
      local c = ls.choice_node
      local f = ls.function_node

      ls.add_snippets("lua", {
        -- Plugin spec for lazy.nvim
        s("plugin", {
          t('{\n  "'),
          i(1, "username/plugin-name"),
          t('",\n  '),
          c(2, {
            t("lazy = true,"),
            t('event = "VeryLazy",'),
            t('ft = "'),
            t('cmd = "'),
            t("keys = {"),
          }),
          t("\n  "),
          c(3, {
            t("opts = {\n    "),
            t('config = function()\n    require("'),
            t('config = function(_, opts)\n    require("'),
          }),
          i(4),
          t("\n  },\n}"),
        }),

        -- Function with LuaDoc
        s("func", {
          t("--- "),
          i(1, "Function description"),
          t({ "", "--- @param " }),
          i(2, "param_name"),
          t(" "),
          i(3, "param_type"),
          t(" "),
          i(4, "param_desc"),
          t({ "", "--- @return " }),
          i(5, "return_type"),
          t(" "),
          i(6, "return_desc"),
          t({ "", "function " }),
          i(7, "func_name"),
          t("("),
          f(function(args)
            return args[1][1]
          end, { 2 }),
          t(")\n  "),
          i(0),
          t({ "", "end" }),
        }),

        -- More snippets can be added here
      })
    end,
  },
}
