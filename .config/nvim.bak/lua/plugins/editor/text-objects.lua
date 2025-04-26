-- ~/.config/nvim/lua/plugins/editor/text-objects.lua
-- Enhanced text objects and motions for more precise editing

return {
  -- Enhanced text objects support
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    event = "BufReadPost",
    config = function()
      require("nvim-treesitter.configs").setup({
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              -- Function-related text objects
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",

              -- Argument/parameter text objects
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",

              -- Conditional text objects
              ["ai"] = "@conditional.outer",
              ["ii"] = "@conditional.inner",

              -- Loop text objects
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",

              -- Comment text objects
              ["a/"] = "@comment.outer",

              -- Block text objects
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",

              -- Call text objects
              ["a:"] = "@call.outer",
              ["i:"] = "@call.inner",
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["<leader>a>"] = "@parameter.inner",
              ["<leader>f>"] = "@function.outer",
            },
            swap_previous = {
              ["<leader>a<"] = "@parameter.inner",
              ["<leader>f<"] = "@function.outer",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner",
              ["]b"] = "@block.outer",
              ["]i"] = "@conditional.outer",
              ["]l"] = "@loop.outer",
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]A"] = "@parameter.inner",
              ["]B"] = "@block.outer",
              ["]I"] = "@conditional.outer",
              ["]L"] = "@loop.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner",
              ["[b"] = "@block.outer",
              ["[i"] = "@conditional.outer",
              ["[l"] = "@loop.outer",
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[A"] = "@parameter.inner",
              ["[B"] = "@block.outer",
              ["[I"] = "@conditional.outer",
              ["[L"] = "@loop.outer",
            },
          },
          lsp_interop = {
            enable = true,
            border = "rounded",
            peek_definition_code = {
              ["<leader>df"] = "@function.outer",
              ["<leader>dF"] = "@class.outer",
            },
          },
        },
      })
    end,
  },

  -- Additional text objects for indent-based operations
  {
    "echasnovski/mini.ai",
    version = "*",
    event = "BufReadPost",
    config = function()
      require("mini.ai").setup({
        n_lines = 500,
        custom_textobjects = {
          -- Indentation text objects
          i = function()
            local ai = require("mini.ai")
            return ai.gen_spec.treesitter({ a = "@block.outer", i = "@block.inner" })
          end,
          -- Entire buffer text object
          e = function()
            local from = { line = 1, col = 1 }
            local to = {
              line = vim.fn.line("$"),
              col = math.max(vim.fn.getline("$"):len(), 1),
            }
            return { from = from, to = to }
          end,
          -- Line text object (without indentation)
          l = function()
            local line = vim.fn.line(".")
            local from = { line = line, col = 1 }
            local to = { line = line, col = math.max(vim.fn.getline(line):len(), 1) }
            return { from = from, to = to }
          end,
          -- Number text object (consecutive digits)
          n = function()
            local line = vim.fn.line(".")
            local col = vim.fn.col(".")
            local line_str = vim.fn.getline(line)

            -- Find numbers before and after cursor
            local from_col, to_col = col, col
            while from_col > 1 and line_str:sub(from_col - 1, from_col - 1):match("%d") do
              from_col = from_col - 1
            end
            while to_col <= #line_str and line_str:sub(to_col, to_col):match("%d") do
              to_col = to_col + 1
            end
            to_col = to_col - 1

            -- Return if there's no number at cursor
            if from_col > to_col then
              return
            end

            return { from = { line = line, col = from_col }, to = { line = line, col = to_col } }
          end,
        },
      })
    end,
  },

  -- Enhanced f/t motions
  {
    "ggandor/flit.nvim",
    event = "BufReadPost",
    dependencies = {
      "ggandor/leap.nvim",
    },
    config = function()
      require("flit").setup({
        keys = { f = "f", F = "F", t = "t", T = "T" },
        labeled_modes = "nv",
        multiline = true,
        opts = {},
      })
    end,
  },

  -- Improved dot repeat for plugins
  {
    "tpope/vim-repeat",
    event = "BufReadPost",
  },

  -- Enhanced % matching
  {
    "andymass/vim-matchup",
    event = "BufReadPost",
    config = function()
      vim.g.matchup_matchparen_offscreen = { method = "popup" }
      vim.g.matchup_surround_enabled = 1
      vim.g.matchup_transmute_enabled = 1

      require("nvim-treesitter.configs").setup({
        matchup = {
          enable = true,
          disable = {},
        },
      })
    end,
  },

  -- Smart column movement
  {
    "albenik/vim-columnmove",
    event = "BufReadPost",
    init = function()
      vim.g.columnmove_strict_wbege = 0
      vim.g.columnmove_no_default_key_mappings = 1

      vim.keymap.set({ "n", "o", "x" }, "<C-,>", "<Plug>(columnmove-b)")
      vim.keymap.set({ "n", "o", "x" }, "<C-.>", "<Plug>(columnmove-e)")
      vim.keymap.set({ "n", "o", "x" }, "<C-m>", "<Plug>(columnmove-w)")
    end,
  },

  -- Enhanced join operations
  {
    "Wansmer/treesj",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      {
        "gJ",
        function()
          require("treesj").join()
        end,
        desc = "Join Syntax Tree",
      },
      {
        "gS",
        function()
          require("treesj").split()
        end,
        desc = "Split Syntax Tree",
      },
      {
        "gT",
        function()
          require("treesj").toggle()
        end,
        desc = "Toggle Split/Join",
      },
    },
    config = function()
      require("treesj").setup({
        use_default_keymaps = false,
        max_join_length = 120,
        cursor_behavior = "start",
        notify = true,
        dot_repeat = true,
        langs = {
          -- Enhanced configuration for popular languages
          lua = require("treesj.langs.lua"),
          python = require("treesj.langs.python"),
          javascript = require("treesj.langs.javascript"),
          typescript = require("treesj.langs.typescript"),
          json = require("treesj.langs.json"),
        },
      })
    end,
  },
}
