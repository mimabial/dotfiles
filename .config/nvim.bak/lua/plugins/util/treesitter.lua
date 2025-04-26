--------------------------------------------------------------------------------
-- Treesitter Configuration
--------------------------------------------------------------------------------
--
-- This module configures Treesitter for advanced syntax highlighting,
-- indentation, and code navigation.
--
-- Features:
-- 1. Syntax highlighting with semantic understanding
-- 2. Intelligent indentation based on language structure
-- 3. Code folding based on syntax tree
-- 4. Advanced text objects for selections
-- 5. Structural editing and navigation
-- 6. Context-aware comment handling
-- 7. Rainbow parentheses for nested structures
--
-- Treesitter dramatically improves the code understanding capabilities
-- of Neovim, enabling more intelligent editing operations.
--------------------------------------------------------------------------------

return {
  -- Core Treesitter plugin
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
    dependencies = {
      -- Better text objects
      "nvim-treesitter/nvim-treesitter-textobjects",
      -- Comment awareness based on syntax tree
      "JoosepAlviste/nvim-ts-context-commentstring",
      -- Context display at the top of the window
      "nvim-treesitter/nvim-treesitter-context",
      -- Rainbow parentheses for nested structures
      "HiPhish/rainbow-delimiters.nvim",
      -- Autoclose and autorename HTML/JSX tags
      "windwp/nvim-ts-autotag",
    },
    keys = {
      { "<c-space>", desc = "Increment Selection", mode = { "n", "x" } },
      { "<bs>", desc = "Decrement Selection", mode = "x" },
    },
    config = function()
      -- Skip slow treesitter highlight in big files
      local function skip_treesitter_highlight(_, bufnr)
        local max_filesize = 100 * 1024 -- 100 KB
        local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(bufnr))
        if ok and stats and stats.size > max_filesize then
          return true
        end
      end

      -- Configure Treesitter
      require("nvim-treesitter.configs").setup({
        -- Install these parsers automatically
        ensure_installed = {
          -- Core languages
          "bash",
          "c",
          "cpp",
          "css",
          "html",
          "javascript",
          "json",
          "lua",
          "markdown",
          "markdown_inline",
          "python",
          "regex",
          "rust",
          "tsx",
          "typescript",
          "vim",
          "vimdoc",
          "yaml",

          -- Additional languages (uncomment as needed)
          -- "c_sharp",
          -- "clojure",
          -- "cmake",
          -- "comment",
          -- "dart",
          -- "dockerfile",
          -- "elixir",
          -- "go",
          -- "gomod",
          -- "graphql",
          -- "haskell",
          -- "java",
          -- "kotlin",
          -- "latex",
          -- "make",
          -- "ocaml",
          -- "php",
          -- "ruby",
          -- "scala",
          -- "sql",
          -- "swift",
          -- "toml",
        },

        -- Module configurations
        highlight = {
          enable = true,
          disable = skip_treesitter_highlight,
          additional_vim_regex_highlighting = false,
        },

        -- Indentation based on treesitter
        indent = {
          enable = true,
          -- Some languages have issues with treesitter-based indentation
          disable = { "yaml", "python", "css" },
        },

        -- Auto close and rename HTML/JSX tags
        autotag = {
          enable = true,
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
            "markdown",
          },
        },

        -- Context-aware commenting
        context_commentstring = {
          enable = true,
          enable_autocmd = false,
          -- JSX/TSX comments in JavaScript/TypeScript files
          config = {
            javascript = {
              __default = "// %s",
              jsx_element = "{/* %s */}",
              jsx_fragment = "{/* %s */}",
              jsx_attribute = "// %s",
              comment = "// %s",
            },
            typescript = {
              __default = "// %s",
              jsx_element = "{/* %s */}",
              jsx_fragment = "{/* %s */}",
              jsx_attribute = "// %s",
              comment = "// %s",
            },
          },
        },

        -- Incremental selection
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",
            node_incremental = "<C-space>",
            scope_incremental = false,
            node_decremental = "<BS>",
          },
        },

        -- Custom text objects for selections
        textobjects = {
          -- Select based on treesitter nodes
          select = {
            enable = true,
            lookahead = true, -- Jump forward to get to the textobj
            keymaps = {
              -- You can use the capture groups defined in textobjects.scm
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",
              ["ai"] = "@conditional.outer",
              ["ii"] = "@conditional.inner",
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["is"] = "@statement.inner",
              ["as"] = "@statement.outer",
              ["aC"] = "@comment.outer",
              ["iC"] = "@comment.inner",
            },
            selection_modes = {
              ["@parameter.outer"] = "v", -- charwise
              ["@block.outer"] = "V", -- linewise
              ["@function.outer"] = "V", -- linewise
              ["@class.outer"] = "V", -- linewise
            },
            include_surrounding_whitespace = false,
          },

          -- Move between text objects
          move = {
            enable = true,
            set_jumps = true, -- whether to set jumps in the jumplist
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner",
              ["]i"] = "@conditional.outer",
              ["]l"] = "@loop.outer",
              ["]s"] = "@statement.outer",
              ["]b"] = "@block.outer",
              ["]z"] = "@fold", -- Custom fold objects
              ["]o"] = "@comment.outer", -- Jump to next comment
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
              ["]A"] = "@parameter.inner",
              ["]I"] = "@conditional.outer",
              ["]L"] = "@loop.outer",
              ["]S"] = "@statement.outer",
              ["]B"] = "@block.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner",
              ["[i"] = "@conditional.outer",
              ["[l"] = "@loop.outer",
              ["[s"] = "@statement.outer",
              ["[b"] = "@block.outer",
              ["[z"] = "@fold", -- Custom fold objects
              ["[o"] = "@comment.outer", -- Jump to previous comment
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
              ["[A"] = "@parameter.inner",
              ["[I"] = "@conditional.outer",
              ["[L"] = "@loop.outer",
              ["[S"] = "@statement.outer",
              ["[B"] = "@block.outer",
            },
          },

          -- Swap elements like parameters or arguments
          swap = {
            enable = true,
            swap_next = {
              ["<leader>sn"] = "@parameter.inner",
              ["<leader>sf"] = "@function.outer",
              ["<leader>se"] = "@element",
            },
            swap_previous = {
              ["<leader>sp"] = "@parameter.inner",
              ["<leader>sF"] = "@function.outer",
              ["<leader>sE"] = "@element",
            },
          },

          -- LSP interop
          lsp_interop = {
            enable = true,
            border = "rounded",
            floating_preview_opts = {},
            peek_definition_code = {
              ["<leader>df"] = "@function.outer",
              ["<leader>dF"] = "@class.outer",
            },
          },
        },
      })

      -- Set up treesitter-based folding
      vim.opt.foldmethod = "expr"
      vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
      vim.opt.foldenable = false -- Don't fold by default

      -- Configure treesitter context (shows context at top of window)
      require("treesitter-context").setup({
        enable = true,
        max_lines = 3, -- Maximum number of lines to show
        min_window_height = 15, -- Minimum window height to enable context
        line_numbers = true,
        multiline_threshold = 20, -- Maximum number of lines for a multiline node
        trim_scope = "outer", -- "inner" or "outer" for innermost/outermost scope
        mode = "cursor", -- "cursor" or "topline"
        separator = nil, -- Separator between context and content
        zindex = 20, -- Z-index of the context window
      })

      -- Configure rainbow delimiters
      local rainbow_delimiters = require("rainbow-delimiters")
      vim.g.rainbow_delimiters = {
        strategy = {
          [""] = rainbow_delimiters.strategy["global"],
          vim = rainbow_delimiters.strategy["local"], -- Use local strategy for vim
        },
        query = {
          [""] = "rainbow-delimiters",
          lua = "rainbow-blocks",
          javascript = "rainbow-delimiters-react",
          typescript = "rainbow-delimiters-react",
          tsx = "rainbow-delimiters-react",
          html = "rainbow-tags",
        },
        highlight = {
          "RainbowDelimiterRed",
          "RainbowDelimiterYellow",
          "RainbowDelimiterBlue",
          "RainbowDelimiterOrange",
          "RainbowDelimiterGreen",
          "RainbowDelimiterViolet",
          "RainbowDelimiterCyan",
        },
        blacklist = { "c", "cpp" }, -- Some languages don't work well with rainbow delimiters
      }

      -- Set up comment awareness for JSX/TSX/etc.
      require("ts_context_commentstring").setup({
        enable_autocmd = false,
      })

      -- Set up autotag for HTML/JSX/etc.
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
          "glimmer",
          "handlebars",
          "hbs",
        },
        skip_tags = {
          "area",
          "base",
          "br",
          "col",
          "command",
          "embed",
          "hr",
          "img",
          "input",
          "keygen",
          "link",
          "meta",
          "param",
          "source",
          "track",
          "wbr",
        },
      })

      -- Define highlight colors for rainbow delimiters
      for i, color in ipairs({
        "#E06C75", -- Red
        "#E5C07B", -- Yellow
        "#61AFEF", -- Blue
        "#D19A66", -- Orange
        "#98C379", -- Green
        "#C678DD", -- Violet
        "#56B6C2", -- Cyan
      }) do
        vim.api.nvim_set_hl(
          0,
          "RainbowDelimiter" .. rainbow_delimiters.highlight[i]:match("[^RainbowDelimiter].*"),
          { fg = color }
        )
      end
    end,
  },

  -- Show code context at the top of the window
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufReadPre",
    enabled = true,
    opts = {
      max_lines = 3, -- Maximum number of lines to show
      min_window_height = 15,
      multiline_threshold = 20,
      separator = "━", -- Nice separator between context and content
    },
    keys = {
      {
        "[c",
        function()
          require("treesitter-context").go_to_context()
        end,
        desc = "Jump to Context",
      },
      {
        "<leader>ut",
        function()
          require("treesitter-context").toggle()
        end,
        desc = "Toggle Context",
      },
    },
  },

  -- Rainbow delimiters for nested parentheses, brackets, etc.
  {
    "HiPhish/rainbow-delimiters.nvim",
    event = "BufReadPost",
  },

  -- Auto-tag (auto-close and auto-rename HTML/JSX tags)
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {},
  },

  -- Context-aware commenting
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    lazy = true,
    opts = {
      enable_autocmd = false,
    },
  },
}
