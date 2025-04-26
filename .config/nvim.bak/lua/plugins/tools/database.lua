-- Database tools configuration
-- Sets up database management and query execution capabilities

return {
  -- Dadbod: database client for Vim
  {
    "tpope/vim-dadbod",
    lazy = true,
    dependencies = {
      "kristijanhusak/vim-dadbod-ui",
      "kristijanhusak/vim-dadbod-completion",
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    init = function()
      -- Load UI on database file types
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          vim.schedule(function()
            require("lazy").load({ plugins = { "vim-dadbod" } })
          end)
        end,
      })

      -- Configure global connection variables
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
      vim.g.db_ui_use_nerd_fonts = true
      vim.g.db_ui_show_database_icon = true
      vim.g.db_ui_win_position = "right"
      vim.g.db_ui_winwidth = 40
    end,
    keys = {
      { "<leader>db", "<cmd>DBUIToggle<CR>", desc = "Toggle Database UI" },
      { "<leader>df", "<cmd>DBUIFindBuffer<CR>", desc = "Find DB Buffer" },
      { "<leader>dr", "<cmd>DBUIRenameBuffer<CR>", desc = "Rename DB Buffer" },
      { "<leader>da", "<cmd>DBUIAddConnection<CR>", desc = "Add DB Connection" },
    },
    config = function()
      -- Setup completion for SQL files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          require("cmp").setup.buffer({
            sources = {
              { name = "vim-dadbod-completion" },
              { name = "buffer" },
            },
          })
        end,
      })
    end,
  },
}
