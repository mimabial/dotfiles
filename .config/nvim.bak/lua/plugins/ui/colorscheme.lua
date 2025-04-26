-- ~/.config/nvim/lua/plugins/colorscheme.lua
-- Colorscheme configuration

return {
  -- Tokyo Night theme
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000, -- Make sure to load this before all the other start plugins
    config = function()
      require("tokyonight").setup({
        style = "night",
        transparent = false,
        styles = {
          comments = { italic = true },
          keywords = { italic = true },
          functions = {},
          variables = {},
        },
        sidebars = { "qf", "help", "terminal", "neo-tree", "oil", "packer" },
        lualine_bold = true,
      })
    end,
  },

  -- Gruvbox Material theme
  {
    "f4z3r/gruvbox-material.nvim",
    name = "gruvbox-material",
    lazy = false,
    priority = 1000,
    config = function()
      require("gruvbox-material").setup({
        italics = true,
        contrast = "hard",
        comments = {
          italics = true,
        },
        background = {
          transparent = false,
        },
        float = {
          force_background = false,
        },
        signs = {
          highlight = true,
        },
      })
    end,
  },

  -- Catppuccin color scheme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha", -- latte, frappe, macchiato, mocha
        background = {
          light = "latte",
          dark = "mocha",
        },
        transparent_background = false,
        term_colors = true,
        dim_inactive = {
          enabled = false,
          shade = "dark",
          percentage = 0.15,
        },
        no_italic = false,
        no_bold = false,
        no_underline = false,
        styles = {
          comments = { "italic" },
          conditionals = { "italic" },
          loops = {},
          functions = {},
          keywords = {},
          strings = {},
          variables = {},
          numbers = {},
          booleans = {},
          properties = {},
          types = {},
          operators = {},
        },
        color_overrides = {},
        custom_highlights = {},
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          telescope = true,
          treesitter = true,
          notify = true,
          mini = true,
          mason = true,
          which_key = true,
          indent_blankline = {
            enabled = true,
            colored_indent_levels = false,
          },
          native_lsp = {
            enabled = true,
            virtual_text = {
              errors = { "italic" },
              hints = { "italic" },
              warnings = { "italic" },
              information = { "italic" },
            },
            underlines = {
              errors = { "underline" },
              hints = { "underline" },
              warnings = { "underline" },
              information = { "underline" },
            },
            inlay_hints = {
              background = true,
            },
          },
          navic = {
            enabled = true,
            custom_bg = "NONE",
          },
        },
      })
    end,
  },
  -- Set the colorscheme
  {
    "LazyVim/LazyVim",
    optional = true,
    config = function()
      -- Apply the colorscheme
      vim.cmd("colorscheme catppuccin")

      -- Keybinding to toggle between light and dark themes
      vim.keymap.set("n", "<leader>ut", function()
        if vim.o.background == "dark" then
          vim.o.background = "light"
          vim.cmd("colorscheme catppuccin-latte")
        else
          vim.o.background = "dark"
          vim.cmd("colorscheme catppuccin-mocha")
        end
      end, { desc = "Toggle Dark/Light Theme" })

      -- Define UI-related commands
      vim.api.nvim_create_user_command("ColorScheme", function(opts)
        vim.cmd("colorscheme " .. opts.args)
      end, { nargs = 1, complete = "color" })
    end,
  },

  -- Color highlight
  {
    "NvChad/nvim-colorizer.lua",
    event = "BufReadPre",
    config = function()
      require("colorizer").setup({
        filetypes = { "*" },
        user_default_options = {
          RGB = true,
          RRGGBB = true,
          names = false,
          RRGGBBAA = true,
          AARRGGBB = false,
          rgb_fn = true,
          hsl_fn = true,
          css = true,
          css_fn = true,
          mode = "background",
          tailwind = true,
          sass = { enable = true, parsers = { "css" } },
          virtualtext = "■",
        },
        buftypes = {},
      })
    end,
  },
}
