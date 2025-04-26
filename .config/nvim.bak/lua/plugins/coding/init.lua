-- ~/.config/nvim/lua/plugins/coding/init.lua
-- Loader for coding assistance plugins

return {
  -- Import all coding enhancement modules
  imports = {
    "plugins.coding.completions",
    "plugins.coding.snippets",
    "plugins.coding.ai",
    "plugins.coding.refactoring",
  },

  -- Common coding plugins that don't fit in specific categories
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
        ts_config = {
          lua = { "string", "source" },
          javascript = { "template_string" },
          typescript = { "template_string" },
        },
        disable_filetype = { "TelescopePrompt", "vim" },
        fast_wrap = {
          map = "<M-e>",
          chars = { "{", "[", "(", '"', "'" },
          pattern = [=[[%'%"%>%]%)%}%,]]=],
          end_key = "$",
          keys = "qwertyuiopzxcvbnmasdfghjkl",
          check_comma = true,
          highlight = "Search",
          highlight_grey = "Comment",
        },
      })
    end,
  },

  -- Auto close HTML/XML tags
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    ft = {
      "html",
      "xml",
      "javascriptreact",
      "typescriptreact",
      "svelte",
      "vue",
      "tsx",
      "jsx",
      "php",
      "markdown",
      "astro",
      "handlebars",
      "hbs",
    },
    config = function()
      require("nvim-ts-autotag").setup({
        enable = true,
        filetypes = {
          "html",
          "xml",
          "javascriptreact",
          "typescriptreact",
          "svelte",
          "vue",
          "tsx",
          "jsx",
          "php",
          "markdown",
          "astro",
          "handlebars",
          "hbs",
        },
      })
    end,
  },

  -- Context-aware commenting
  {
    "numToStr/Comment.nvim",
    event = "BufRead",
    dependencies = {
      "JoosepAlviste/nvim-ts-context-commentstring",
    },
    config = function()
      require("Comment").setup({
        padding = true,
        sticky = true,
        ignore = "^$",
        toggler = {
          line = "gcc",
          block = "gbc",
        },
        opleader = {
          line = "gc",
          block = "gb",
        },
        extra = {
          above = "gcO",
          below = "gco",
          eol = "gcA",
        },
        mappings = {
          basic = true,
          extra = true,
        },
        pre_hook = function(ctx)
          local U = require("Comment.utils")

          -- Determine whether to use linewise or blockwise commentstring
          local type = ctx.ctype == U.ctype.linewise and "__default" or "__multiline"

          -- Determine the location where to calculate commentstring from
          local location = nil
          if ctx.ctype == U.ctype.blockwise then
            location = require("ts_context_commentstring.utils").get_cursor_location()
          elseif ctx.cmotion == U.cmotion.v or ctx.cmotion == U.cmotion.V then
            location = require("ts_context_commentstring.utils").get_visual_start_location()
          end

          return require("ts_context_commentstring.internal").calculate_commentstring({
            key = type,
            location = location,
          })
        end,
      })
    end,
  },

  -- Enhanced syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua",
          "vim",
          "vimdoc",
          "query",
          "python",
          "javascript",
          "typescript",
          "tsx",
          "html",
          "css",
          "rust",
          "go",
          "c",
          "cpp",
          "java",
          "kotlin",
          "bash",
          "markdown",
          "json",
          "yaml",
          "toml",
          "dockerfile",
          "cmake",
          "make",
          "sql",
        },
        sync_install = false,
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        indent = {
          enable = true,
        },
        context_commentstring = {
          enable = true,
          enable_autocmd = false,
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",
            node_incremental = "<C-space>",
            scope_incremental = "<C-s>",
            node_decremental = "<C-backspace>",
          },
        },
        playground = {
          enable = true,
          disable = {},
          updatetime = 25,
          persist_queries = false,
          keybindings = {
            toggle_query_editor = "o",
            toggle_hl_groups = "i",
            toggle_injected_languages = "t",
            toggle_anonymous_nodes = "a",
            toggle_language_display = "I",
            focus_language = "f",
            unfocus_language = "F",
            update = "R",
            goto_node = "<cr>",
            show_help = "?",
          },
        },
      })
    end,
  },

  -- Improved indentation detection
  {
    "tpope/vim-sleuth",
    event = "BufReadPre",
  },

  -- Highlight using colors the color codes in files
  {
    "norcalli/nvim-colorizer.lua",
    event = "BufReadPre",
    config = function()
      require("colorizer").setup({
        "*",
        css = { css = true },
        scss = { css = true },
        html = { css = true, javascript = true },
        javascript = { css_fn = true },
        typescript = { css_fn = true },
      })
    end,
  },

  -- Show indentation guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = "BufReadPre",
    config = function()
      require("ibl").setup({
        indent = {
          char = "│",
          tab_char = "│",
        },
        scope = {
          enabled = true,
          show_start = false,
          show_end = false,
          injected_languages = true,
          highlight = { "Function", "Label" },
          priority = 500,
        },
        exclude = {
          filetypes = {
            "help",
            "alpha",
            "dashboard",
            "neo-tree",
            "Trouble",
            "lazy",
            "mason",
            "notify",
            "toggleterm",
            "lazyterm",
          },
          buftypes = {
            "terminal",
            "nofile",
            "quickfix",
            "prompt",
          },
        },
      })
    end,
  },

  -- Show code structure with symbols
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen", "AerialInfo" },
    keys = {
      { "<leader>cs", "<cmd>AerialToggle<CR>", desc = "Toggle Symbols Outline" },
    },
    config = function()
      require("aerial").setup({
        layout = {
          width = 0.25,
          default_direction = "right",
          placement = "edge",
        },
        filter_kind = {
          "Class",
          "Constructor",
          "Enum",
          "Function",
          "Interface",
          "Method",
          "Struct",
          "Module",
          "Package",
          "Property",
          "Field",
          "TypeParameter",
          "Constant",
          "Variable",
          "Namespace",
        },
        show_guides = true,
        guides = {
          mid_item = "├─",
          last_item = "└─",
          nested_top = "│ ",
          whitespace = "  ",
        },
        keymaps = {
          ["<CR>"] = "actions.jump",
          ["p"] = "actions.jump",
          ["<C-v>"] = "actions.jump_vsplit",
          ["<C-s>"] = "actions.jump_split",
          ["q"] = "actions.close",
          ["o"] = "actions.tree_toggle",
          ["O"] = "actions.tree_toggle_recursive",
          ["l"] = "actions.tree_open",
          ["h"] = "actions.tree_close",
          ["r"] = "actions.centered",
        },
        icons = {
          Array = "󰅨 ",
          Boolean = " ",
          Class = "󰠱 ",
          Constant = "󰏿 ",
          Constructor = " ",
          Enum = " ",
          EnumMember = " ",
          Event = " ",
          Field = " ",
          File = "󰈙 ",
          Function = "󰊕 ",
          Interface = " ",
          Key = "󰌋 ",
          Method = "󰆧 ",
          Module = "󰏗 ",
          Namespace = "󰌗 ",
          Null = "󰟢 ",
          Number = "󰎠 ",
          Object = "󰅩 ",
          Operator = "󰆕 ",
          Package = "󰏖 ",
          Property = "󰜢 ",
          String = "󰀬 ",
          Struct = "󰙅 ",
          TypeParameter = "󰊄 ",
          Variable = "󰀫 ",
        },
      })
    end,
  },

  -- Enhanced TODO comments
  {
    "folke/todo-comments.nvim",
    event = "BufReadPre",
    keys = {
      { "<leader>ct", "<cmd>TodoTelescope<CR>", desc = "Find TODOs" },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("todo-comments").setup({
        signs = true,
        keywords = {
          FIX = {
            icon = " ",
            color = "error",
            alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
          },
          TODO = {
            icon = " ",
            color = "info",
          },
          HACK = {
            icon = " ",
            color = "warning",
          },
          WARN = {
            icon = " ",
            color = "warning",
            alt = { "WARNING", "XXX" },
          },
          PERF = {
            icon = " ",
            color = "default",
            alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" },
          },
          NOTE = {
            icon = " ",
            color = "hint",
            alt = { "INFO" },
          },
          TEST = {
            icon = "⏲ ",
            color = "test",
            alt = { "TESTING", "PASSED", "FAILED" },
          },
        },
        gui_style = {
          fg = "NONE",
          bg = "BOLD",
        },
        merge_keywords = true,
        highlight = {
          before = "",
          keyword = "wide",
          after = "fg",
          pattern = [[.*<(KEYWORDS)\s*:]], -- Match "<keyword>:"
          comments_only = true,
          max_line_len = 400,
          exclude = {},
        },
        colors = {
          error = { "DiagnosticError", "ErrorMsg", "#DC2626" },
          warning = { "DiagnosticWarning", "WarningMsg", "#FBBF24" },
          info = { "DiagnosticInfo", "#2563EB" },
          hint = { "DiagnosticHint", "#10B981" },
          default = { "Identifier", "#7C3AED" },
          test = { "Identifier", "#FF00FF" },
        },
        search = {
          command = "rg",
          args = {
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
          },
          pattern = [[\b(KEYWORDS):]],
        },
      })
    end,
  },
}
