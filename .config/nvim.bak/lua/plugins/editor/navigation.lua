-- ~/.config/nvim/lua/plugins/editor/navigation.lua
-- Navigation enhancements for faster movement within buffers and projects

return {
  -- Leap for precise motion
  {
    "ggandor/leap.nvim",
    dependencies = {
      "tpope/vim-repeat",
    },
    event = "BufReadPost",
    config = function()
      local leap = require("leap")
      leap.setup({
        case_insensitive = true,
        labels = {
          "s",
          "f",
          "n",
          "j",
          "k",
          "l",
          "h",
          "o",
          "d",
          "w",
          "e",
          "m",
          "b",
          "u",
          "y",
          "v",
          "r",
          "g",
          "t",
          "c",
          "x",
          "/",
          "z",
          "S",
          "F",
          "N",
          "J",
          "K",
          "L",
          "H",
          "O",
          "D",
          "W",
          "E",
          "M",
          "B",
          "U",
          "Y",
          "V",
          "R",
          "G",
          "T",
          "C",
          "X",
          "?",
          "Z",
        },
        safe_labels = {
          "s",
          "f",
          "n",
          "u",
          "t",
          "/",
        },
      })

      -- Keymappings
      vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap-forward)")
      vim.keymap.set({ "n", "x", "o" }, "S", "<Plug>(leap-backward)")
    end,
  },

  -- Enhanced file explorer
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "Toggle Explorer" },
      { "<leader>ef", "<cmd>Neotree focus<CR>", desc = "Focus Explorer" },
    },
    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        enable_git_status = true,
        enable_diagnostics = true,
        sort_case_insensitive = true,
        window = {
          width = 30,
          mappings = {
            ["<space>"] = "none",
            ["o"] = "open",
            ["H"] = "navigate_up",
            ["<bs>"] = "navigate_up",
            ["."] = "set_root",
            ["I"] = "toggle_hidden",
            ["R"] = "refresh",
            ["/"] = "fuzzy_finder",
            ["f"] = "filter_on_submit",
            ["<c-x>"] = "clear_filter",
            ["a"] = { "add", config = { show_path = "relative" } },
            ["d"] = "delete",
            ["r"] = "rename",
            ["y"] = "copy_to_clipboard",
            ["x"] = "cut_to_clipboard",
            ["p"] = "paste_from_clipboard",
            ["c"] = { "copy", config = { show_path = "relative" } },
            ["m"] = { "move", config = { show_path = "relative" } },
          },
        },
        filesystem = {
          follow_current_file = { enabled = true },
          use_libuv_file_watcher = true,
          filtered_items = {
            visible = false,
            hide_dotfiles = false,
            hide_gitignored = true,
            hide_by_name = {
              ".git",
              ".DS_Store",
              "thumbs.db",
              "node_modules",
            },
            never_show = {
              ".git",
              ".DS_Store",
              "thumbs.db",
            },
          },
        },
        buffers = {
          follow_current_file = { enabled = true },
          group_empty_dirs = true,
        },
        git_status = {
          window = {
            position = "float",
            mappings = {
              ["A"] = "git_add_all",
              ["u"] = "git_unstage_file",
              ["a"] = "git_add_file",
              ["r"] = "git_revert_file",
              ["c"] = "git_commit",
              ["p"] = "git_push",
              ["g"] = "git_commit_and_push",
            },
          },
        },
      })
    end,
  },

  -- Enhanced buffer navigation
  {
    "akinsho/bufferline.nvim",
    event = "BufReadPost",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    version = "*",
    keys = {
      { "<leader>bp", "<cmd>BufferLinePick<CR>", desc = "Pick Buffer" },
      { "<leader>bc", "<cmd>BufferLinePickClose<CR>", desc = "Pick & Close Buffer" },
      { "<leader>bl", "<cmd>BufferLineCloseLeft<CR>", desc = "Close Left Buffers" },
      { "<leader>br", "<cmd>BufferLineCloseRight<CR>", desc = "Close Right Buffers" },
      { "<leader>bo", "<cmd>BufferLineCloseOthers<CR>", desc = "Close Other Buffers" },
      { "<leader>bP", "<cmd>BufferLineTogglePin<CR>", desc = "Toggle Pin Buffer" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<CR>", desc = "Previous Buffer" },
      { "<S-l>", "<cmd>BufferLineCycleNext<CR>", desc = "Next Buffer" },
      { "<C-p>", "<cmd>BufferLineMovePrev<CR>", desc = "Move Buffer Left" },
      { "<C-n>", "<cmd>BufferLineMoveNext<CR>", desc = "Move Buffer Right" },
    },
    config = function()
      require("bufferline").setup({
        options = {
          mode = "buffers",
          close_command = "bdelete! %d",
          right_mouse_command = "bdelete! %d",
          left_mouse_command = "buffer %d",
          middle_mouse_command = nil,
          indicator = {
            icon = "▎",
            style = "icon",
          },
          buffer_close_icon = "",
          modified_icon = "●",
          close_icon = "",
          left_trunc_marker = "",
          right_trunc_marker = "",
          max_name_length = 18,
          max_prefix_length = 15,
          tab_size = 18,
          diagnostics = "nvim_lsp",
          diagnostics_update_in_insert = false,
          diagnostics_indicator = function(count, level)
            local icon = level:match("error") and " " or " "
            return " " .. icon .. count
          end,
          offsets = {
            {
              filetype = "neo-tree",
              text = "File Explorer",
              text_align = "center",
              separator = true,
            },
          },
          show_buffer_icons = true,
          show_buffer_close_icons = true,
          show_close_icon = true,
          show_tab_indicators = true,
          persist_buffer_sort = true,
          separator_style = "thin",
          enforce_regular_tabs = false,
          always_show_bufferline = true,
          sort_by = "insert_at_end",
        },
      })
    end,
  },

  -- Fuzzy file navigation (specific config for navigation)
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files hidden=true<CR>", desc = "Find Files" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find Buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Recent Files" },
      { "<leader>fw", "<cmd>Telescope live_grep<CR>", desc = "Find Word" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help Tags" },
      { "<leader>fp", "<cmd>Telescope projects<CR>", desc = "Projects" },
      { "<leader>fc", "<cmd>Telescope commands<CR>", desc = "Commands" },
      { "<leader>fm", "<cmd>Telescope marks<CR>", desc = "Marks" },
      { "<leader>fk", "<cmd>Telescope keymaps<CR>", desc = "Keymaps" },
    },
    config = function()
      -- Telescope navigation-specific config
      -- Main config in telescope.lua, this just adds navigation-specific options
      require("telescope").setup({
        defaults = {
          layout_strategy = "horizontal",
          layout_config = {
            prompt_position = "top",
            width = 0.8,
            height = 0.8,
            preview_width = 0.5,
          },
          sorting_strategy = "ascending",
          path_display = { "truncate" },
          file_ignore_patterns = {
            "^.git/",
            "^node_modules/",
            "^__pycache__/",
          },
          mappings = {
            i = {
              ["<C-j>"] = "move_selection_next",
              ["<C-k>"] = "move_selection_previous",
              ["<C-n>"] = "cycle_history_next",
              ["<C-p>"] = "cycle_history_prev",
              ["<C-c>"] = "close",
              ["<C-d>"] = "delete_buffer",
              ["<C-u>"] = false,
            },
          },
        },
      })
    end,
  },

  -- Harpoon for quick file navigation between frequent files
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    keys = {
      {
        "<leader>ha",
        function()
          require("harpoon"):list():append()
        end,
        desc = "Add File to Harpoon",
      },
      {
        "<leader>hh",
        function()
          require("harpoon").ui:toggle_quick_menu(require("harpoon"):list())
        end,
        desc = "Harpoon Menu",
      },
      {
        "<leader>h1",
        function()
          require("harpoon"):list():select(1)
        end,
        desc = "Harpoon File 1",
      },
      {
        "<leader>h2",
        function()
          require("harpoon"):list():select(2)
        end,
        desc = "Harpoon File 2",
      },
      {
        "<leader>h3",
        function()
          require("harpoon"):list():select(3)
        end,
        desc = "Harpoon File 3",
      },
      {
        "<leader>h4",
        function()
          require("harpoon"):list():select(4)
        end,
        desc = "Harpoon File 4",
      },
      {
        "<leader>hj",
        function()
          require("harpoon"):list():prev()
        end,
        desc = "Prev Harpoon File",
      },
      {
        "<leader>hk",
        function()
          require("harpoon"):list():next()
        end,
        desc = "Next Harpoon File",
      },
    },
    config = function()
      require("harpoon").setup({
        menu = {
          width = 60,
          height = 10,
        },
        settings = {
          save_on_toggle = true,
          sync_on_ui_close = true,
          key = function()
            return vim.loop.cwd()
          end,
        },
      })
    end,
  },

  -- Better project navigation
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    config = function()
      require("project_nvim").setup({
        detection_methods = { "pattern", "lsp" },
        patterns = {
          ".git",
          "package.json",
          "Cargo.toml",
          "pyproject.toml",
          "setup.py",
          "Makefile",
          "requirements.txt",
          "CMakeLists.txt",
          "build.gradle",
          ".project",
          "go.mod",
        },
        show_hidden = false,
        silent_chdir = true,
        scope_chdir = "global",
      })
    end,
  },

  -- Better terminal navigation
  {
    "numToStr/Navigator.nvim",
    event = "VeryLazy",
    config = function()
      require("Navigator").setup({
        disable_on_zoom = true,
        save_when_buffer_changed = true,
      })

      vim.keymap.set({ "n", "t" }, "<C-h>", "<CMD>NavigatorLeft<CR>", { desc = "Navigate Left" })
      vim.keymap.set({ "n", "t" }, "<C-l>", "<CMD>NavigatorRight<CR>", { desc = "Navigate Right" })
      vim.keymap.set({ "n", "t" }, "<C-k>", "<CMD>NavigatorUp<CR>", { desc = "Navigate Up" })
      vim.keymap.set({ "n", "t" }, "<C-j>", "<CMD>NavigatorDown<CR>", { desc = "Navigate Down" })
    end,
  },
}
