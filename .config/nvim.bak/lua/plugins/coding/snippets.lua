-- lua/plugins/coding/snippets.lua
-- Snippet configuration for NeoCode
-- This file configures and integrates snippet support into the completion system

local M = {}

function M.setup()
  return {
    -- LuaSnip: advanced snippet engine
    {
      "L3MON4D3/LuaSnip",
      dependencies = {
        "rafamadriz/friendly-snippets", -- Collection of snippets for many languages
        "honza/vim-snippets", -- Additional snippet collection
      },
      config = function()
        local luasnip = require("luasnip")
        local types = require("luasnip.util.types")

        -- Load friendly-snippets
        require("luasnip.loaders.from_vscode").lazy_load()
        -- Load vim-snippets
        require("luasnip.loaders.from_snipmate").lazy_load()

        -- Custom snippets folder in the config
        require("luasnip.loaders.from_vscode").lazy_load({
          paths = vim.fn.stdpath("config") .. "/snippets",
        })

        -- Configure LuaSnip
        luasnip.config.set_config({
          history = true, -- Keep track of snippet history for undo
          updateevents = "TextChanged,TextChangedI", -- Update snippets as you type
          enable_autosnippets = true, -- Enable automatic snippets
          ext_opts = {
            [types.choiceNode] = { -- Visual highlight for choice nodes
              active = {
                virt_text = { { "●", "DiagnosticHint" } },
              },
            },
            [types.insertNode] = { -- Visual highlight for insert nodes
              active = {
                virt_text = { { "●", "DiagnosticInfo" } },
              },
            },
          },
        })

        -- Keymaps for snippet navigation
        vim.keymap.set({ "i", "s" }, "<C-j>", function()
          if luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          end
        end, { silent = true, desc = "Expand snippet or jump to next placeholder" })

        vim.keymap.set({ "i", "s" }, "<C-k>", function()
          if luasnip.jumpable(-1) then
            luasnip.jump(-1)
          end
        end, { silent = true, desc = "Jump to previous placeholder" })

        vim.keymap.set({ "i", "s" }, "<C-l>", function()
          if luasnip.choice_active() then
            luasnip.change_choice(1)
          end
        end, { silent = true, desc = "Cycle through choices" })
      end,
    },

    -- nvim-cmp integration for snippets
    {
      "hrsh7th/nvim-cmp",
      optional = true,
      dependencies = {
        "saadparwaiz1/cmp_luasnip", -- LuaSnip completion source
      },
      opts = function(_, opts)
        -- Add LuaSnip as a completion source
        local cmp = require("cmp")
        local luasnip = require("luasnip")

        opts.snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        }

        -- Add cmp_luasnip source
        table.insert(opts.sources, {
          name = "luasnip",
          priority = 750, -- High priority, just below LSP
          keyword_length = 2,
          option = {
            show_autosnippets = true,
            use_show_condition = true,
          },
        })

        -- Add keybinding for confirming snippets
        opts.mapping = vim.tbl_extend("force", opts.mapping or {}, {
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.confirm({ select = true })
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
        })
      end,
    },

    -- Custom snippet filetype detection
    {
      "nathom/filetype.nvim",
      optional = true,
      opts = function(_, opts)
        opts = opts or {}
        opts.overrides = vim.tbl_deep_extend("force", opts.overrides or {}, {
          extensions = {
            ["snippets"] = "snippets",
          },
        })
        return opts
      end,
    },

    -- Language-specific snippet configurations
    -- These will be loaded by the language modules
    _snippets = {
      -- Helper function to register language-specific snippets
      register = function(lang, snippets)
        local ls = require("luasnip")
        local s = ls.snippet
        local t = ls.text_node
        local i = ls.insert_node
        local f = ls.function_node
        local c = ls.choice_node
        local d = ls.dynamic_node
        local r = ls.restore_node
        local fmt = require("luasnip.extras.fmt").fmt
        local rep = require("luasnip.extras").rep

        -- Add the snippets to the specific language
        ls.add_snippets(lang, snippets)
      end,

      -- Load project-specific snippets
      load_project_snippets = function()
        local luasnip = require("luasnip")
        local project_dir = vim.fn.getcwd()
        local project_snippets = project_dir .. "/.neocode/snippets"

        if vim.fn.isdirectory(project_snippets) == 1 then
          require("luasnip.loaders.from_vscode").lazy_load({
            paths = project_snippets,
          })
        end
      end,
    },
  }
end

return M
