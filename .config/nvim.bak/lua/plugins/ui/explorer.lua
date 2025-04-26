-- File explorer configuration
-- Sets up a file browser for project navigation

return {
  -- Neo-tree: file explorer with git integration
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "Toggle Explorer" },
      { "<leader>o", "<cmd>Neotree focus<CR>", desc = "Focus Explorer" },
    },
    init = function()
      -- Close Neo-tree when a file is opened
      vim.api.nvim_create_autocmd("TermClose", {
        pattern = "*lazygit",
        callback = function()
          if package.loaded["neo-tree.sources.git_status"] then
            require("neo-tree.sources.git_status").refresh()
          end
        end,
      })
    end,
    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = true,
        window = {
          width = 35,
          mappings = {
            ["<space>"] = "none", -- Disable space mapping
            ["o"] = "open",
            ["H"] = "prev_source",
            ["L"] = "next_source",
            ["h"] = function(state)
              local node = state.tree:get_node()
              if node.type == "directory" and node:is_expanded() then
                require("neo-tree.sources.filesystem").toggle_directory(state, node)
              else
                require("neo-tree.ui.renderer").focus_node(state, node:get_parent_id())
              end
            end,
            ["l"] = function(state)
              local node = state.tree:get_node()
              if node.type == "directory" then
                require("neo-tree.sources.filesystem").toggle_directory(state, node)
              else
                require("neo-tree.actions").open(state)
              end
            end,
          },
        },
        filesystem = {
          follow_current_file = {
            enabled = true,
            leave_dirs_open = true,
          },
          use_libuv_file_watcher = true,
          filtered_items = {
            visible = false,
            hide_dotfiles = false,
            hide_gitignored = false,
            hide_by_name = {
              ".git",
              "node_modules",
              ".cache",
            },
            never_show = {
              ".DS_Store",
              "thumbs.db",
            },
          },
        },
        git_status = {
          symbols = {
            added = "✚",
            modified = "",
            deleted = "✖",
            renamed = "",
            untracked = "",
            ignored = "",
            unstaged = "",
            staged = "",
            conflict = "",
          },
        },
        document_symbols = {
          kinds = {
            File = { icon = "📄", hl = "Tag" },
            Namespace = { icon = "📦", hl = "Include" },
            Package = { icon = "📦", hl = "Label" },
            Class = { icon = "🔶", hl = "Include" },
            Property = { icon = "ﰠ", hl = "@property" },
            Enum = { icon = "", hl = "@number" },
            Function = { icon = "", hl = "Function" },
            String = { icon = "🔤", hl = "String" },
            Number = { icon = "#", hl = "Number" },
            Array = { icon = "", hl = "Type" },
            Object = { icon = "⦿", hl = "Type" },
            Key = { icon = "🔑", hl = "" },
            Struct = { icon = "𝓢", hl = "Type" },
            Operator = { icon = "+", hl = "Operator" },
            TypeParameter = { icon = "𝙏", hl = "Type" },
            StaticMethod = { icon = "", hl = "Function" },
          },
        },
      })
    end,
  },
}
