-- Statusline configuration
-- Sets up an informative and visually appealing status line

return {
  -- Lualine: fast and feature-rich statusline
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "auto",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          globalstatus = true,
          disabled_filetypes = {
            statusline = { "dashboard", "lazy", "alpha" },
          },
        },
        sections = {
          lualine_a = {
            {
              "mode",
              fmt = function(str)
                return str:sub(1, 1)
              end,
            },
          },
          lualine_b = {
            "branch",
            {
              "diff",
              symbols = { added = " ", modified = " ", removed = " " },
            },
          },
          lualine_c = {
            {
              "diagnostics",
              sources = { "nvim_diagnostic" },
              symbols = { error = " ", warn = " ", info = " ", hint = " " },
            },
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            {
              "filename",
              path = 1, -- Show relative path
              symbols = {
                modified = "●", -- Text to show when the file is modified
                readonly = "", -- Text to show when the file is non-modifiable or readonly
                unnamed = "[No Name]", -- Text to show for unnamed buffers
              },
            },
          },
          lualine_x = {
            -- LSP server name
            {
              function()
                local clients = vim.lsp.get_active_clients({ bufnr = 0 })
                if #clients == 0 then
                  return "No LSP"
                end
                local names = {}
                for _, client in ipairs(clients) do
                  table.insert(names, client.name)
                end
                return table.concat(names, ", ")
              end,
              icon = " ",
            },
            "encoding",
            "fileformat",
            "filetype",
          },
          lualine_y = {
            -- Current function/method
            {
              function()
                local navic = require("nvim-navic")
                if navic.is_available() then
                  local loc = navic.get_location()
                  if loc and loc ~= "" then
                    return loc:gsub("%%", "%%%%") -- Escape % characters
                  end
                end
                return ""
              end,
              cond = function()
                local navic = package.loaded["nvim-navic"]
                return navic and navic.is_available()
              end,
            },
          },
          lualine_z = {
            { "location", padding = { left = 1, right = 1 } },
            { "progress", padding = { left = 0, right = 1 } },
          },
        },
        extensions = { "nvim-tree", "toggleterm", "quickfix" },
      })
    end,
  },

  -- Navic: shows code context in the statusline
  {
    "SmiteshP/nvim-navic",
    lazy = true,
    init = function()
      vim.g.navic_silence = true
    end,
    opts = {
      icons = {
        File = " ",
        Module = " ",
        Namespace = " ",
        Package = " ",
        Class = " ",
        Method = " ",
        Property = " ",
        Field = " ",
        Constructor = " ",
        Enum = " ",
        Interface = " ",
        Function = " ",
        Variable = " ",
        Constant = " ",
        String = " ",
        Number = " ",
        Boolean = " ",
        Array = " ",
        Object = " ",
        Key = " ",
        Null = " ",
        EnumMember = " ",
        Struct = " ",
        Event = " ",
        Operator = " ",
        TypeParameter = " ",
      },
      lsp = {
        auto_attach = true,
      },
      highlight = true,
      separator = " > ",
      depth_limit = 5,
      depth_limit_indicator = "...",
    },
  },
}
