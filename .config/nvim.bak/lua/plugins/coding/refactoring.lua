-- ~/.config/nvim/lua/plugins/coding/refactoring.lua
-- Code refactoring tools and capabilities

return {
  -- Enhanced refactoring capabilities
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "Refactor" },
    keys = {
      { "<leader>re", ":Refactor extract ", desc = "Extract to Function" },
      { "<leader>rf", ":Refactor extract_to_file ", desc = "Extract to File" },
      { "<leader>rv", ":Refactor extract_var ", desc = "Extract Variable" },
      { "<leader>ri", ":Refactor inline_var ", desc = "Inline Variable" },
      { "<leader>rI", ":Refactor inline_func ", desc = "Inline Function" },
      { "<leader>rb", ":Refactor extract_block ", desc = "Extract Block" },
      { "<leader>rbf", ":Refactor extract_block_to_file ", desc = "Extract Block to File" },
      {
        "<leader>rr",
        function()
          require("telescope").extensions.refactoring.refactors()
        end,
        mode = { "n", "x" },
        desc = "Select Refactor",
      },
      {
        "<leader>re",
        function()
          require("refactoring").refactor("Extract Function")
        end,
        mode = "x",
        desc = "Extract Function",
      },
      {
        "<leader>rv",
        function()
          require("refactoring").refactor("Extract Variable")
        end,
        mode = "x",
        desc = "Extract Variable",
      },
    },
    config = function()
      require("refactoring").setup({
        prompt_func_return_type = {
          go = true,
          java = true,
          cpp = true,
          c = true,
          typescript = true,
          rust = true,
        },
        prompt_func_param_type = {
          go = true,
          java = true,
          cpp = true,
          c = true,
          typescript = true,
          rust = true,
        },
      })

      -- Load telescope extension
      require("telescope").load_extension("refactoring")
    end,
  },

  -- Intelligent code actions
  {
    "weilbith/nvim-code-action-menu",
    cmd = "CodeActionMenu",
    keys = {
      { "<leader>ca", "<cmd>CodeActionMenu<CR>", desc = "Code Action Menu" },
    },
    config = function()
      vim.g.code_action_menu_show_details = true
      vim.g.code_action_menu_show_diff = true
      vim.g.code_action_menu_window_border = "rounded"
    end,
  },

  -- Advanced rename functionality
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    keys = {
      {
        "<leader>rn",
        function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end,
        expr = true,
        desc = "Rename Symbol",
      },
    },
    config = function()
      require("inc_rename").setup({
        input_buffer_type = "dressing",
        show_message = true,
        preview_empty_name = true,
        highlight_references = true,
        prepend_current_word = true,
      })
    end,
  },

  -- Handle function arguments better
  {
    "mizlan/iswap.nvim",
    cmd = { "ISwap", "ISwapWith", "ISwapNode", "ISwapNodeWith" },
    keys = {
      { "<leader>cs", "<cmd>ISwapWith<CR>", desc = "Swap Selection" },
      { "<leader>cp", "<cmd>ISwapNodeWith<CR>", desc = "Swap Parameter" },
    },
    config = function()
      require("iswap").setup({
        keys = "asdfghjklqwertyuiopzxcvbnm",
        grey = "disable",
        hl_snipe = "CursorLineNr",
        hl_selection = "Visual",
        hl_grey = "Comment",
        flash_style = "simultaneous",
        autoswap = true,
      })
    end,
  },

  -- Structural search and replace
  {
    "cshuaimin/ssr.nvim",
    keys = {
      {
        "<leader>sr",
        function()
          require("ssr").open()
        end,
        mode = { "n", "x" },
        desc = "Structural Search & Replace",
      },
    },
    config = function()
      require("ssr").setup({
        border = "rounded",
        min_width = 50,
        min_height = 5,
        max_width = 120,
        max_height = 25,
        keymaps = {
          close = "q",
          next_match = "n",
          prev_match = "N",
          replace_confirm = "<cr>",
          replace_all = "<leader><cr>",
        },
      })
    end,
  },

  -- Split/join blocks of code
  {
    "AndrewRadev/splitjoin.vim",
    keys = {
      { "gS", "<Plug>SplitjoinSplit", desc = "Split Code Block" },
      { "gJ", "<Plug>SplitjoinJoin", desc = "Join Code Block" },
    },
    init = function()
      vim.g.splitjoin_split_mapping = ""
      vim.g.splitjoin_join_mapping = ""
      vim.g.splitjoin_trailing_comma = 1
      vim.g.splitjoin_python_brackets_on_separate_lines = 1
      vim.g.splitjoin_java_argument_split_first_comma = 0
    end,
  },

  -- Search case conversion
  {
    "tpope/vim-abolish",
    event = "BufReadPost",
    keys = {
      { "<leader>rs", "<Plug>(abolish-coerce-word)", desc = "Coerce Case Style" },
    },
  },

  -- Auto-fix diagnostics
  {
    "folke/trouble.nvim",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    cmd = { "Trouble", "TroubleToggle", "TroubleClose", "TroubleRefresh" },
    keys = {
      { "<leader>xx", "<cmd>TroubleToggle<CR>", desc = "Toggle Diagnostics" },
      { "<leader>xw", "<cmd>TroubleToggle workspace_diagnostics<CR>", desc = "Workspace Diagnostics" },
      { "<leader>xd", "<cmd>TroubleToggle document_diagnostics<CR>", desc = "Document Diagnostics" },
      { "<leader>xq", "<cmd>TroubleToggle quickfix<CR>", desc = "Quickfix List" },
      { "<leader>xl", "<cmd>TroubleToggle loclist<CR>", desc = "Location List" },
      { "gR", "<cmd>TroubleToggle lsp_references<CR>", desc = "LSP References" },
      { "<leader>ra", "<cmd>TroubleToggle lsp_definitions<CR>", desc = "LSP Definitions" },
    },
    config = function()
      require("trouble").setup({
        position = "bottom",
        height = 10,
        width = 50,
        icons = true,
        mode = "workspace_diagnostics",
        severity = nil,
        fold_open = "",
        fold_closed = "",
        group = true,
        padding = true,
        cycle_results = true,
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
        indent_lines = true,
        auto_open = false,
        auto_close = false,
        auto_preview = true,
        auto_fold = false,
        auto_jump = { "lsp_definitions" },
        use_diagnostic_signs = true,
      })
    end,
  },

  -- Quickfix enhancements
  {
    "kevinhwang91/nvim-bqf",
    ft = "qf",
    config = function()
      require("bqf").setup({
        auto_enable = true,
        auto_resize_height = true,
        preview = {
          win_height = 12,
          win_vheight = 12,
          delay_syntax = 80,
          border = "rounded",
          show_title = false,
          should_preview_cb = function(bufnr, qwinid)
            local ret = true
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local fsize = vim.fn.getfsize(bufname)
            if fsize > 100 * 1024 then
              ret = false
            elseif bufname:match("^fugitive://") then
              ret = false
            end
            return ret
          end,
        },
        func_map = {
          open = "<CR>",
          openc = "o",
          drop = "O",
          split = "<C-s>",
          vsplit = "<C-v>",
          tab = "t",
          tabb = "T",
          tabc = "<C-t>",
          tabdrop = "",
          ptogglemode = "z,",
          ptoggleitem = "z.",
          ptoggleauto = "za",
          filter = "zn",
          filterr = "zN",
          fzffilter = "zf",
        },
      })
    end,
  },
}
