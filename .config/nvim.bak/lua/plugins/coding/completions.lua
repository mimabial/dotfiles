--------------------------------------------------------------------------------
-- Code Completion Configuration
--------------------------------------------------------------------------------
--
-- This module configures intelligent code completion with:
-- 1. nvim-cmp - Main completion engine
-- 2. LuaSnip - Snippet engine
-- 3. Various completion sources (LSP, snippets, buffer, path, etc.)
-- 4. UI customization for the completion menu
-- 5. Enhanced documentation display
--
-- The completion system prioritizes:
-- - LSP suggestions (with documentation and signatures)
-- - Snippets for common patterns
-- - AI completions (from Codeium/Copilot)
-- - Context-aware completions from the current buffer
-- - File paths and environment variables
--------------------------------------------------------------------------------

return {
  -- Main completion plugin
  {
    "hrsh7th/nvim-cmp",
    version = false, -- Using the latest instead of a specific version
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      -- Snippet engine and its completion source
      {
        "L3MON4D3/LuaSnip",
        dependencies = {
          -- Collection of preconfigured snippets for various languages
          "rafamadriz/friendly-snippets",
          -- Additional language-specific snippets
          "iurimateus/luasnip-latex-snippets.nvim",
        },
        build = "make install_jsregexp", -- For improved regex support
        config = function()
          -- Load snippets from friendly-snippets
          require("luasnip.loaders.from_vscode").lazy_load()
          -- Load custom snippets from snippets directory
          require("luasnip.loaders.from_vscode").lazy_load({
            paths = { vim.fn.stdpath("config") .. "/snippets" },
          })
          -- Load LaTeX snippets
          require("luasnip-latex-snippets").setup({
            use_treesitter = true,
          })

          -- Setup LuaSnip
          local ls = require("luasnip")
          ls.setup({
            history = true, -- Keep track of snippet history
            updateevents = "TextChanged,TextChangedI", -- Update snippets in realtime
            delete_check_events = "TextChanged,InsertLeave", -- When to check for deleted snippets
            enable_autosnippets = true, -- Enable automatic snippets
            ext_opts = {
              [require("luasnip.util.types").choiceNode] = {
                active = {
                  virt_text = { { " « Current Choice » ", "Comment" } },
                },
              },
            },
          })

          -- Keyboard shortcuts for navigating snippets
          vim.keymap.set({ "i", "s" }, "<C-j>", function()
            if ls.expand_or_jumpable() then
              ls.expand_or_jump()
            end
          end, { silent = true, desc = "Expand snippet or jump to next placeholder" })

          vim.keymap.set({ "i", "s" }, "<C-k>", function()
            if ls.jumpable(-1) then
              ls.jump(-1)
            end
          end, { silent = true, desc = "Jump to previous snippet placeholder" })

          vim.keymap.set({ "i", "s" }, "<C-l>", function()
            if ls.choice_active() then
              ls.change_choice(1)
            end
          end, { silent = true, desc = "Cycle forward through snippet choices" })

          vim.keymap.set({ "i", "s" }, "<C-h>", function()
            if ls.choice_active() then
              ls.change_choice(-1)
            end
          end, { silent = true, desc = "Cycle backward through snippet choices" })
        end,
      },

      -- Sources for nvim-cmp
      "hrsh7th/cmp-nvim-lsp", -- LSP completions
      "hrsh7th/cmp-buffer", -- Buffer completions
      "hrsh7th/cmp-path", -- Path completions
      "hrsh7th/cmp-cmdline", -- Command line completions
      "hrsh7th/cmp-nvim-lua", -- Neovim Lua API completions
      "saadparwaiz1/cmp_luasnip", -- Snippet completions
      "hrsh7th/cmp-nvim-lsp-signature-help", -- Parameter completions
      "hrsh7th/cmp-nvim-lsp-document-symbol", -- Document symbol completions
      "onsails/lspkind.nvim", -- VS Code-like pictograms
      "roobert/tailwindcss-colorizer-cmp.nvim", -- Tailwind CSS colors in completion
      "petertriho/cmp-git", -- Git completions
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      local lspkind = require("lspkind")
      local compare = require("cmp.config.compare")
      require("tailwindcss-colorizer-cmp").setup({ color_square_width = 2 })

      -- Helper function to check for text before cursor
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      -- Main nvim-cmp configuration
      cmp.setup({
        -- Use LuaSnip as the snippet engine
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },

        -- Customize the completion windows
        window = {
          completion = cmp.config.window.bordered({
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None",
            col_offset = -3,
            side_padding = 0,
          }),
          documentation = cmp.config.window.bordered({
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None",
          }),
        },

        -- Customize the completion menu
        formatting = {
          fields = { "kind", "abbr", "menu" },
          format = function(entry, vim_item)
            local kind = lspkind.cmp_format({
              mode = "symbol_text",
              maxwidth = 50,
              ellipsis_char = "...",
              show_labelDetails = true,
              menu = {
                buffer = "[Buffer]",
                nvim_lsp = "[LSP]",
                luasnip = "[Snippet]",
                nvim_lua = "[Lua]",
                path = "[Path]",
                codeium = "[AI]",
                copilot = "[AI]",
                calc = "[Calc]",
              },
              before = function(_, vim_item)
                -- Optional colorization for Tailwind CSS classes
                return require("tailwindcss-colorizer-cmp").formatter(_, vim_item)
              end,
            })(entry, vim_item)

            return kind
          end,
        },

        -- Configure key mappings for completion menu interaction
        mapping = cmp.mapping.preset.insert({
          -- Scroll the documentation window
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),

          -- Open/close the completion menu
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),

          -- Accept the selected completion item
          ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = false, -- Only confirm explicitly selected items
          }),

          -- Navigate completion items
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, { "i", "s" }),

          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),

        -- Configure the sources for completions (in order of priority)
        sources = cmp.config.sources({
          { name = "nvim_lsp", priority = 1000 },
          { name = "nvim_lsp_signature_help", priority = 900 },
          { name = "luasnip", priority = 800 },
          -- AI completion sources would be inserted here by the AI modules
          {
            name = "buffer",
            priority = 700,
            option = {
              get_bufnrs = function()
                return vim.api.nvim_list_bufs()
              end,
              keyword_length = 3,
            },
          },
          { name = "path", priority = 600 },
          { name = "nvim_lua", priority = 500 },
          { name = "calc", priority = 400 },
          { name = "emoji", priority = 300 },
          { name = "treesitter", priority = 200 },
        }),

        -- Configure sorting for completion items
        sorting = {
          priority_weight = 2,
          comparators = {
            -- Deprioritize snippets under other completion items
            function(entry1, entry2)
              local kind1 = entry1:get_kind()
              local kind2 = entry2:get_kind()
              if kind1 == kind2 then
                return nil
              end
              if kind1 == cmp.lsp_item_kind.Snippet then
                return false
              end
              if kind2 == cmp.lsp_item_kind.Snippet then
                return true
              end
              return nil
            end,
            compare.offset,
            compare.exact,
            compare.score,
            compare.recently_used,
            compare.locality,
            compare.kind,
            compare.sort_text,
            compare.length,
            compare.order,
          },
        },

        -- Experimental features
        experimental = {
          ghost_text = {
            hl_group = "Comment",
          },
        },
      })

      -- Configure git source for commit messages and branches
      require("cmp_git").setup({
        filetypes = { "gitcommit", "octo", "NeogitCommitMessage" },
        github = {
          issues = {
            filter = "all", -- "assigned", "created", "mentioned", "subscribed"
            limit = 100,
            state = "open", -- "open", "closed", "all"
          },
          pull_requests = {
            limit = 100,
            state = "open", -- "open", "closed", "merged", "all"
          },
        },
        gitlab = {
          issues = {
            limit = 100,
            state = "opened", -- "opened", "closed", "all"
          },
          merge_requests = {
            limit = 100,
            state = "opened", -- "opened", "closed", "locked", "merged", "all"
          },
        },
      })

      -- Set up completion for command mode (`:`)
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
          { name = "cmdline" },
        }),
        formatting = {
          fields = { "abbr", "kind" },
          format = function(_, vim_item)
            vim_item.kind = ""
            return vim_item
          end,
        },
      })

      -- Set up completion for search mode (`/`)
      cmp.setup.cmdline({ "/", "?" }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
        formatting = {
          fields = { "abbr", "kind" },
          format = function(_, vim_item)
            vim_item.kind = ""
            return vim_item
          end,
        },
      })

      -- Auto pairs integration
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local handlers = require("nvim-autopairs.completion.handlers")

      cmp.event:on(
        "confirm_done",
        cmp_autopairs.on_confirm_done({
          filetypes = {
            -- Disable for specific filetypes
            ["*"] = {
              ["("] = {
                kind = {
                  cmp.lsp_item_kind.Function,
                  cmp.lsp_item_kind.Method,
                },
                handler = handlers["*"],
              },
            },
            -- Disable for specific languages
            tex = false,
            markdown = false,
          },
        })
      )

      -- Add borders to documentation window
      local win = require("cmp.utils.window")

      local _win_open = win.open
      win.open = function(self, opts)
        local new_opts = vim.tbl_extend("force", opts or {}, {
          border = "rounded",
        })
        return _win_open(self, new_opts)
      end
    end,
  },

  -- Additional completion related plugins

  -- Auto pairs for brackets, quotes, etc.
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true, -- Use treesitter to check for pairs
        ts_config = {
          lua = { "string", "source" }, -- Don't add pairs in lua string treesitter nodes
          javascript = { "string", "template_string" }, -- Don't add pairs in javascript template_string
        },
        fast_wrap = {
          map = "<M-e>", -- Mapping to wrap with pairs
          chars = { "{", "[", "(", '"', "'" },
          pattern = [=[[%'%"%>%]%)%}%,]]=],
          end_key = "$",
          keys = "qwertyuiopzxcvbnmasdfghjkl",
          check_comma = true,
          manual_position = false,
          highlight = "Search",
          highlight_grey = "Comment",
        },
        disable_filetype = { "TelescopePrompt", "vim" },
      })
    end,
  },

  -- Auto completion for HTML/JSX tags
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    dependencies = "nvim-treesitter/nvim-treesitter",
    config = function()
      require("nvim-ts-autotag").setup({
        filetypes = {
          "html",
          "xml",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "svelte",
          "vue",
          "tsx",
          "jsx",
          "rescript",
          "php",
          "markdown",
          "astro",
          "handlebars",
          "hbs",
          "glimmer",
        },
      })
    end,
  },

  -- Enhanced parameter hints
  {
    "ray-x/lsp_signature.nvim",
    event = "VeryLazy",
    opts = {
      bind = true,
      handler_opts = {
        border = "rounded",
      },
      hint_enable = true,
      hint_prefix = "🔍 ",
      hint_scheme = "String",
      hi_parameter = "Search",
      toggle_key = "<C-k>", -- Toggle signature on and off in insert mode
      select_signature_key = "<C-n>", -- Cycle between signatures
      floating_window = true,
      doc_lines = 10,
      max_width = 80,
      always_trigger = false,
      timer_interval = 200,
      extra_trigger_chars = { "(", ",", "{" },
    },
    config = function(_, opts)
      require("lsp_signature").setup(opts)
    end,
  },

  -- Comment completion and templates
  {
    "danymat/neogen",
    dependencies = "nvim-treesitter/nvim-treesitter",
    config = function()
      require("neogen").setup({
        enabled = true,
        input_after_comment = true, -- Positions cursor inside a generated comment
        snippet_engine = "luasnip", -- Use LuaSnip for templates
        languages = {
          python = {
            template = {
              annotation_convention = "google_docstrings", -- Can be: reST, numpydoc, google_docstrings, sphinx
            },
          },
          typescript = {
            template = {
              annotation_convention = "tsdoc", -- Can be: tsdoc, jsdoc
            },
          },
          typescriptreact = {
            template = {
              annotation_convention = "tsdoc",
            },
          },
          javascript = {
            template = {
              annotation_convention = "jsdoc",
            },
          },
          javascriptreact = {
            template = {
              annotation_convention = "jsdoc",
            },
          },
          lua = {
            template = {
              annotation_convention = "emmylua",
            },
          },
          java = {
            template = {
              annotation_convention = "javadoc",
            },
          },
          c = {
            template = {
              annotation_convention = "doxygen",
            },
          },
          cpp = {
            template = {
              annotation_convention = "doxygen",
            },
          },
          php = {
            template = {
              annotation_convention = "phpdoc",
            },
          },
          rust = {
            template = {
              annotation_convention = "rustdoc",
            },
          },
          go = {
            template = {
              annotation_convention = "godoc",
            },
          },
        },
      })

      -- Add keymaps for generating documentation
      vim.keymap.set("n", "<leader>cd", require("neogen").generate, { desc = "Generate Documentation" })

      -- Add additional keymaps for specific type of documentation
      vim.keymap.set("n", "<leader>cdf", function()
        require("neogen").generate({ type = "func" })
      end, { desc = "Generate Function Doc" })

      vim.keymap.set("n", "<leader>cdc", function()
        require("neogen").generate({ type = "class" })
      end, { desc = "Generate Class Doc" })

      vim.keymap.set("n", "<leader>cdt", function()
        require("neogen").generate({ type = "type" })
      end, { desc = "Generate Type Doc" })

      vim.keymap.set("n", "<leader>cdf", function()
        require("neogen").generate({ type = "file" })
      end, { desc = "Generate File Doc" })
    end,
  },
}
