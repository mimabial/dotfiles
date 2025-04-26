--------------------------------------------------------------------------------
-- Telescope Configuration
--------------------------------------------------------------------------------
--
-- This module configures Telescope, a highly extensible fuzzy finder.
--
-- Features:
-- 1. Fuzzy finding for files, buffers, and text
-- 2. Integration with LSP for symbols and references
-- 3. Git integration for branches, commits, and status
-- 4. Custom sorters and previewers for better results
-- 5. Selection history and resume functionality
-- 6. Extension system for additional functionality
-- 7. Key mappings for quick access to common operations
--
-- Telescope is the main navigation tool in this configuration, providing
-- a unified interface for finding and selecting items across Neovim.
--------------------------------------------------------------------------------

return {
  -- Main Telescope plugin
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    version = false, -- Use latest release
    dependencies = {
      -- Required dependencies
      "nvim-lua/plenary.nvim",

      -- Faster sorter
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },

      -- UI for vim.ui.select
      "nvim-telescope/telescope-ui-select.nvim",

      -- Extensions
      "nvim-telescope/telescope-live-grep-args.nvim", -- Advanced grep
      "benfowler/telescope-luasnip.nvim", -- Snippet browser
      "nvim-telescope/telescope-file-browser.nvim", -- File browser
      "nvim-telescope/telescope-project.nvim", -- Project management
      "nvim-telescope/telescope-symbols.nvim", -- Symbol browser
      "LinArcX/telescope-env.nvim", -- Environment vars
      "nvim-telescope/telescope-media-files.nvim", -- Preview media files
      "dhruvmanila/telescope-bookmarks.nvim", -- Browser bookmarks
      "LukasPietzschmann/telescope-tabs", -- Tab management
    },
    keys = {
      -- File operations
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent Files" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fs", "<cmd>Telescope live_grep<cr>", desc = "Find Text" },
      { "<leader>fS", "<cmd>Telescope grep_string<cr>", desc = "Find Current Word" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Find Current Word" },
      {
        "<leader>fW",
        function()
          require("telescope.builtin").grep_string({ word_match = "-w" })
        end,
        desc = "Find Exact Word",
      },
      { "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Fuzzy Find (Buffer)" },

      -- LSP operations
      { "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document Symbols" },
      { "<leader>lS", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Workspace Symbols" },
      { "<leader>lr", "<cmd>Telescope lsp_references<cr>", desc = "References" },
      { "<leader>ld", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document Diagnostics" },
      { "<leader>lD", "<cmd>Telescope diagnostics<cr>", desc = "Workspace Diagnostics" },
      { "<leader>la", "<cmd>Telescope lsp_code_actions<cr>", desc = "Code Actions" },

      -- Git operations
      { "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Git Commits" },
      { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git Status" },
      { "<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Git Branches" },
      { "<leader>gf", "<cmd>Telescope git_files<cr>", desc = "Git Files" },

      -- Help and commands
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
      { "<leader>fc", "<cmd>Telescope commands<cr>", desc = "Commands" },
      { "<leader>f:", "<cmd>Telescope command_history<cr>", desc = "Command History" },
      { "<leader>f/", "<cmd>Telescope search_history<cr>", desc = "Search History" },
      { "<leader>ft", "<cmd>Telescope filetypes<cr>", desc = "Filetypes" },
      { "<leader>fm", "<cmd>Telescope marks<cr>", desc = "Jump to Mark" },

      -- Extensions
      { "<leader>fp", "<cmd>Telescope project<cr>", desc = "Projects" },
      { "<leader>fn", "<cmd>Telescope notify<cr>", desc = "Notifications" },
      { "<leader>fB", "<cmd>Telescope file_browser<cr>", desc = "File Browser" },
      { "<leader>fE", "<cmd>Telescope env<cr>", desc = "Environment Variables" },
      { "<leader>fM", "<cmd>Telescope bookmarks<cr>", desc = "Browser Bookmarks" },
      { "<leader>fT", "<cmd>Telescope tabs<cr>", desc = "Tabs" },
      { "<leader>fi", "<cmd>Telescope symbols<cr>", desc = "Insert Symbol" },

      -- Advanced grep with arguments
      {
        "<leader>fG",
        function()
          require("telescope").extensions.live_grep_args.live_grep_args()
        end,
        desc = "Live Grep (Args)",
      },

      -- Resume last search
      { "<leader>fR", "<cmd>Telescope resume<cr>", desc = "Resume Last Search" },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")
      local layout = require("telescope.actions.layout")
      local themes = require("telescope.themes")

      -- Get custom mappings from user settings if available
      local user_mappings = {}
      local ok, user_settings = pcall(require, "config.settings")
      if ok and user_settings.telescope and user_settings.telescope.mappings then
        user_mappings = user_settings.telescope.mappings
      end

      -- Configure Telescope
      telescope.setup({
        defaults = {
          -- Appearance
          prompt_prefix = "   ",
          selection_caret = " ",
          entry_prefix = "  ",
          sorting_strategy = "ascending",
          layout_strategy = "horizontal",
          layout_config = {
            horizontal = {
              prompt_position = "top",
              preview_width = 0.55,
              results_width = 0.8,
            },
            vertical = {
              mirror = false,
            },
            width = 0.87,
            height = 0.80,
            preview_cutoff = 120,
          },

          -- Behavior
          path_display = { "truncate" },
          dynamic_preview_title = true,

          -- UI elements
          winblend = 0,
          border = {},
          borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
          color_devicons = true,

          -- File operations
          file_sorter = require("telescope.sorters").get_fuzzy_file,
          file_ignore_patterns = {
            "node_modules",
            ".git/",
            "dist/",
            "build/",
            "%.lock",
            "%.min.js",
            "vendor/",
            ".cache/",
            ".vscode/",
            "__pycache__/",
            "%.o",
            "%.a",
            "%.out",
            "%.class",
            "%.pdf",
            "%.mkv",
            "%.mp4",
            "%.zip",
          },

          -- Text operations
          generic_sorter = require("telescope.sorters").get_generic_fuzzy_sorter,
          set_env = { ["COLORTERM"] = "truecolor" },

          -- Previewers
          file_previewer = require("telescope.previewers").vim_buffer_cat.new,
          grep_previewer = require("telescope.previewers").vim_buffer_vimgrep.new,
          qflist_previewer = require("telescope.previewers").vim_buffer_qflist.new,
          buffer_previewer_maker = require("telescope.previewers").buffer_previewer_maker,

          -- Mappings
          mappings = {
            i = vim.tbl_extend("force", {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-n>"] = actions.cycle_history_next,
              ["<C-p>"] = actions.cycle_history_prev,
              ["<C-c>"] = actions.close,
              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,
              ["<C-f>"] = actions.preview_scrolling_down,
              ["<C-b>"] = actions.preview_scrolling_up,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
              ["<C-l>"] = actions.complete_tag,
              ["<C-/>"] = actions.which_key,
              ["<C-w>"] = { "<c-s-w>", type = "command" },
              ["<C-s>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,
              ["<M-p>"] = layout.toggle_preview,
              ["<M-m>"] = layout.toggle_mirror,
              ["<M-h>"] = layout.cycle_layout_prev,
              ["<M-l>"] = layout.cycle_layout_next,
              ["<M-i>"] = layout.cycle_layout_next,
            }, user_mappings.i or {}),

            n = vim.tbl_extend("force", {
              ["<esc>"] = actions.close,
              ["q"] = actions.close,
              ["<CR>"] = actions.select_default,
              ["<C-s>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
              ["j"] = actions.move_selection_next,
              ["k"] = actions.move_selection_previous,
              ["H"] = actions.move_to_top,
              ["M"] = actions.move_to_middle,
              ["L"] = actions.move_to_bottom,
              ["<Down>"] = actions.move_selection_next,
              ["<Up>"] = actions.move_selection_previous,
              ["gg"] = actions.move_to_top,
              ["G"] = actions.move_to_bottom,
              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,
              ["?"] = actions.which_key,
              ["p"] = layout.toggle_preview,
            }, user_mappings.n or {}),
          },

          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--hidden",
            "--glob=!.git/",
          },
        },

        -- Configure pickers
        pickers = {
          find_files = {
            hidden = true,
            previewer = false,
            find_command = { "fd", "--type", "f", "--strip-cwd-prefix", "--hidden", "--exclude", ".git" },
          },
          live_grep = {
            debounce = 300,
            previewer = true,
            additional_args = function(opts)
              return { "--hidden", "--glob=!.git/" }
            end,
          },
          grep_string = {
            only_sort_text = true,
            use_regex = true,
          },
          buffers = {
            sort_lastused = true,
            theme = "dropdown",
            previewer = false,
            mappings = {
              i = {
                ["<C-d>"] = actions.delete_buffer,
              },
              n = {
                ["dd"] = actions.delete_buffer,
              },
            },
          },
          colorscheme = {
            enable_preview = true,
          },
          lsp_document_symbols = {
            symbol_width = 40,
          },
          oldfiles = {
            prompt_title = "Recent Files",
          },
        },

        -- Configure extensions
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
          live_grep_args = {
            auto_quoting = true,
            mappings = {
              i = {
                ["<C-k>"] = require("telescope-live-grep-args.actions").quote_prompt(),
                ["<C-i>"] = require("telescope-live-grep-args.actions").quote_prompt({ postfix = " --iglob " }),
              },
            },
          },
          ["ui-select"] = {
            themes.get_dropdown({
              -- even more opts
              width = 0.8,
              previewer = false,
              prompt_title = false,
              borderchars = {
                { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
                prompt = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
                results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
                preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
              },
            }),
          },
          file_browser = {
            theme = "dropdown",
            hijack_netrw = true,
            mappings = {
              ["i"] = {
                ["<C-w>"] = function()
                  vim.cmd("normal vbd")
                end,
              },
              ["n"] = {
                ["h"] = require("telescope._extensions.file_browser.actions").goto_parent_dir,
                ["l"] = actions.select_default,
              },
            },
          },
          project = {
            base_dirs = {
              { path = "~/projects", max_depth = 2 },
              { path = "~/.config/nvim", max_depth = 2 },
            },
            hidden_files = true,
            sync_with_nvim_tree = true,
          },
        },
      })

      -- Load extensions
      telescope.load_extension("fzf")
      telescope.load_extension("ui-select")
      telescope.load_extension("live_grep_args")
      telescope.load_extension("file_browser")
      telescope.load_extension("project")
      telescope.load_extension("luasnip")
      telescope.load_extension("env")
      telescope.load_extension("notify")
      telescope.load_extension("media_files")
      telescope.load_extension("tabs")
      pcall(telescope.load_extension, "dap") -- Load if available
      pcall(telescope.load_extension, "bookmarks") -- Load if available

      -- Set up media files preview
      telescope.extensions.media_files.setup({
        filetypes = { "png", "jpg", "jpeg", "gif", "webp", "pdf" },
        find_cmd = "rg",
      })
    end,
  },

  -- Faster sorter for Telescope
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
    lazy = true,
  },

  -- Project management
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    config = function()
      require("project_nvim").setup({
        detection_methods = { "pattern", "lsp" },
        patterns = { ".git", "Makefile", "package.json", "pyproject.toml", "Cargo.toml" },
        silent_chdir = true,
        show_hidden = false,
        scope_chdir = "global",
        datapath = vim.fn.stdpath("data"),
      })
    end,
  },

  -- Enhanced undo tree with Telescope integration
  {
    "debugloop/telescope-undo.nvim",
    keys = {
      { "<leader>fu", "<cmd>Telescope undo<cr>", desc = "Undo History" },
    },
    config = function()
      require("telescope").load_extension("undo")
    end,
  },

  -- File heatmap based on frecency
  {
    "nvim-telescope/telescope-frecency.nvim",
    dependencies = { "kkharji/sqlite.lua" },
    keys = {
      { "<leader>fF", "<cmd>Telescope frecency<cr>", desc = "Frecency" },
    },
    config = function()
      require("telescope").load_extension("frecency")
    end,
  },
}
