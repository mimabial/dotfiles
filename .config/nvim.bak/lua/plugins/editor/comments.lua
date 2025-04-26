-- lua/plugins/editor/comments.lua
-- Comment management for NeoCode
-- This file configures plugins for handling code comments, including toggling, navigation, and formatting

local M = {}

function M.setup()
  return {
    -- Comment.nvim provides smart commenting features
    {
      "numToStr/Comment.nvim",
      event = { "BufReadPost", "BufNewFile" },
      dependencies = {
        -- Optional treesitter integration
        "JoosepAlviste/nvim-ts-context-commentstring",
      },
      config = function()
        -- Setup Comment.nvim
        require("Comment").setup({
          -- Enable smart commenting features
          pre_hook = function(ctx)
            -- Handle language-specific comment strings via treesitter
            local U = require("Comment.utils")

            -- Determine whether to use linewise or blockwise commentstring
            local type = ctx.ctype == U.ctype.linewise and "__default" or "__multiline"

            -- Use treesitter to determine the comment string for the location
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

          -- Set default comment patterns (fallbacks for when ts-context isn't available)
          mappings = {
            -- Operator-pending mappings for comment operations
            basic = true,
            -- Extra comment mappings
            extra = true,
          },

          -- Customize the key mappings
          toggler = {
            line = "gcc", -- Line comment toggle
            block = "gbc", -- Block comment toggle
          },

          -- Comment operations (used with motions)
          opleader = {
            line = "gc", -- Line comment operator
            block = "gb", -- Block comment operator
          },
        })

        -- Configure ts-context-commentstring
        require("ts_context_commentstring").setup({
          enable_autocmd = false, -- Comment.nvim handles this
          -- Set language-specific configurations
          languages = {
            javascript = {
              __default = "// %s",
              jsx_element = "{/* %s */}",
              jsx_fragment = "{/* %s */}",
              jsx_attribute = "// %s",
              comment = "// %s",
            },
            typescript = {
              __default = "// %s",
              __multiline = "/* %s */",
            },
            css = "/* %s */",
            scss = "// %s",
            html = "<!-- %s -->",
            svelte = "<!-- %s -->",
            vue = "<!-- %s -->",
            astro = "<!-- %s -->",
            handlebars = "{{!-- %s --}}",
          },
        })

        -- Additional keymaps for comment operations
        vim.keymap.set(
          "n",
          "<leader>cc",
          "<cmd>lua require('Comment.api').toggle.linewise.current()<CR>",
          { desc = "Toggle comment on current line" }
        )
        vim.keymap.set(
          "v",
          "<leader>cc",
          "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>",
          { desc = "Toggle comment on selection" }
        )
        vim.keymap.set(
          "n",
          "<leader>cC",
          "<cmd>lua require('Comment.api').toggle.blockwise.current()<CR>",
          { desc = "Toggle block comment on current line" }
        )
        vim.keymap.set(
          "v",
          "<leader>cC",
          "<ESC><cmd>lua require('Comment.api').toggle.blockwise(vim.fn.visualmode())<CR>",
          { desc = "Toggle block comment on selection" }
        )
      end,
    },

    -- Todo comments highlighting
    {
      "folke/todo-comments.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
      event = { "BufReadPost", "BufNewFile" },
      opts = {
        signs = true, -- Show icons in the sign column
        keywords = {
          FIX = {
            icon = " ", -- Icon used for the sign, and in search results
            color = "error", -- Can be a hex color, or a named color
            alt = { "FIXME", "BUG", "FIXIT", "ISSUE", "ERROR" }, -- Alternative keywords
          },
          TODO = { icon = " ", color = "info" },
          HACK = { icon = " ", color = "warning" },
          WARN = { icon = " ", color = "warning", alt = { "WARNING", "ATTENTION" } },
          PERF = { icon = " ", color = "default", alt = { "PERFORMANCE", "OPTIMIZE" } },
          NOTE = { icon = " ", color = "hint", alt = { "INFO" } },
          TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
        },
        merge_keywords = true,
        highlight = {
          before = "", -- "fg" or "bg" or empty
          keyword = "wide", -- "fg", "bg", "wide", "wide_bg", "wide_fg" or empty
          after = "fg", -- "fg" or "bg" or empty
          pattern = [[.*<(KEYWORDS)\s*:]], -- Pattern used for highlighting
          comments_only = true, -- Only highlight in comments
          max_line_len = 400, -- Ignore lines longer than this
          exclude = {}, -- List of file types to exclude highlighting
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
          pattern = [[\b(KEYWORDS):]], -- Ripgrep regex
        },
      },
      config = function(_, opts)
        require("todo-comments").setup(opts)

        -- Add keymaps for todo navigation and searching
        vim.keymap.set("n", "]t", function()
          require("todo-comments").jump_next()
        end, { desc = "Next todo comment" })

        vim.keymap.set("n", "[t", function()
          require("todo-comments").jump_prev()
        end, { desc = "Previous todo comment" })

        vim.keymap.set("n", "<leader>ct", "<cmd>TodoTelescope<CR>", { desc = "Find todo comments" })
      end,
    },
  }
end

return M
