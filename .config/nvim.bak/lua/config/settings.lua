--------------------------------------------------------------------------------
-- User Settings
--------------------------------------------------------------------------------
--
-- This file contains your personal customizations.
-- It will not be overwritten when updating the configuration.
--
-- Examples of common customizations are provided below. Uncomment and modify
-- as needed.
--------------------------------------------------------------------------------

local M = {}

-- Personal user information
vim.g.user_name = "Your Name"
vim.g.user_email = "your.email@example.com"

-- Colorscheme and UI preferences
-- Uncomment to change the default theme
-- vim.cmd.colorscheme("tokyonight")

-- Custom UI settings
vim.opt.relativenumber = true -- Enable relative line numbering
vim.opt.number = true -- Show current line number
vim.opt.cursorline = true -- Highlight current line
vim.opt.wrap = false -- Don't wrap lines by default

-- Font settings (if using GUI Neovim)
-- vim.opt.guifont = "JetBrainsMono Nerd Font:h11"

-- Indentation preferences
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.tabstop = 2 -- Number of spaces a tab counts for

-- Folding settings
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldenable = false -- Don't fold by default when opening files

-- Add custom global keymappings
-- Example: mappings that don't conflict with the defaults
vim.keymap.set("n", "<leader>S", ":wa<CR>", { desc = "Save all buffers" })
vim.keymap.set("n", "<leader>Q", ":qa<CR>", { desc = "Quit all" })

-- Default formatters for various filetypes
M.formatters = {
  lua = { "stylua" },
  python = { "black", "isort" },
  javascript = { "prettier" },
  typescript = { "prettier" },
  json = { "prettier" },
  markdown = { "prettier" },
  -- Add more as needed
}

-- Language server configurations
M.lsp = {
  format_on_save = true, -- Format files on save
  inlay_hints = true, -- Show type hints inline

  -- Override specific LSP server settings
  servers = {
    -- Example: custom pyright settings
    pyright = {
      settings = {
        python = {
          analysis = {
            typeCheckingMode = "basic", -- Choose: "off", "basic", "strict"
          },
        },
      },
    },

    -- Example: custom tsserver settings
    tsserver = {
      settings = {
        typescript = {
          inlayHints = {
            includeInlayParameterNameHints = "all",
          },
        },
      },
    },
  },
}

-- AI assistance settings
M.ai = {
  -- Choose your preferred AI provider
  -- Options: "codeium", "copilot", "none"
  provider = "codeium",

  -- Auto-suggestions settings
  suggestions = {
    auto_trigger = true,
    keymap_accept = "<C-y>", -- Key to accept suggestion
    keymap_next = "<C-n>", -- Key to go to next suggestion
    keymap_prev = "<C-p>", -- Key to go to previous suggestion
    keymap_dismiss = "<C-e>", -- Key to dismiss suggestion
  },

  -- AI model preference for gen.nvim
  preferred_model = "claude-3-opus-20240229",
}

-- Project-specific settings
M.project_settings = {
  -- Example: Settings for a Python project
  ["~/projects/python_project"] = {
    lsp = {
      format_on_save = true,
      python = {
        venv_path = ".venv",
        linting = true,
      },
    },
  },

  -- Example: Settings for a JavaScript project
  ["~/projects/js_project"] = {
    lsp = {
      format_on_save = true,
      formatters = {
        javascript = { "prettier" },
        typescript = { "prettier" },
      },
      eslint = {
        enable = true,
        fix_on_save = true,
      },
    },
    plugins = {
      -- Enable specific plugins only for this project
      copilot = {
        enable = true,
      },
    },
  },
}

-- Debug adapter configurations
M.dap = {
  -- Example: Custom debug configurations
  configurations = {
    python = {
      {
        type = "python",
        request = "launch",
        name = "Flask",
        module = "flask",
        args = {
          "run",
          "--no-debugger",
          "--no-reload",
        },
        env = {
          FLASK_APP = "${file}",
          FLASK_ENV = "development",
        },
      },
    },
  },
}

-- Telescope customizations
M.telescope = {
  -- Customize Telescope behavior
  defaults = {
    sorting_strategy = "ascending",
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = {
        prompt_position = "top",
        preview_width = 0.55,
      },
    },
  },
  -- Custom key mappings
  mappings = {
    i = {
      ["<C-j>"] = "move_selection_next",
      ["<C-k>"] = "move_selection_previous",
      ["<C-c>"] = "close",
    },
  },
}

-- Additional plugins
M.plugins = {
  -- Example: Add custom plugins here
  -- They will be added to the plugin manager
  {
    "github_username/plugin_name",
    enabled = true,
    config = function()
      -- Plugin configuration here
    end,
  },
}

-- Theme customizations
M.theme = {
  -- Override specific highlight groups
  highlights = {
    -- Example: Change comment color
    -- Comment = { fg = "#777777", italic = true },

    -- Example: Change status line colors
    -- StatusLine = { bg = "#333344", fg = "#ffffff" },
  },
}

-- Terminal settings
M.terminal = {
  shell = vim.fn.executable("fish") == 1 and "fish" or "bash",
  size = {
    horizontal = 15,
    vertical = 100,
  },
  position = "float", -- Options: "float", "horizontal", "vertical"
}

-- Load user settings at startup
local function apply_user_settings()
  -- Apply project-specific settings if in a known project
  local cwd = vim.fn.getcwd()
  for project_path, settings in pairs(M.project_settings) do
    local expanded_path = vim.fn.expand(project_path)
    if cwd:find(expanded_path, 1, true) == 1 then
      -- We're in this project, apply its settings

      -- Example: Apply LSP settings
      if settings.lsp then
        if settings.lsp.format_on_save ~= nil then
          -- Override format on save for this project
          vim.b.format_on_save = settings.lsp.format_on_save
        end

        -- More project-specific settings could be applied here
      end

      -- Break after finding the first matching project
      break
    end
  end
end

-- Set up an autocmd to apply settings when entering a buffer
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    apply_user_settings()
  end,
})

-- Apply settings immediately on startup
apply_user_settings()

return M
