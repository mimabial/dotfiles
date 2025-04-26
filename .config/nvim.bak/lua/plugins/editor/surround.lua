-- lua/plugins/editor/surround.lua
-- Text surroundings management for NeoCode
-- This file configures plugins for handling surroundings like quotes, parentheses, tags, etc.

local M = {}

function M.setup()
  return {
    -- nvim-surround for adding/changing/deleting surrounding characters
    {
      "kylechui/nvim-surround",
      event = { "BufReadPost", "BufNewFile" },
      version = "*", -- Use the latest stable version
      opts = {
        -- Configuration for nvim-surround
        keymaps = {
          insert = "<C-g>s", -- Insert mode surround
          insert_line = "<C-g>S", -- Insert mode surround on new lines
          normal = "ys", -- Normal mode surround
          normal_cur = "yss", -- Normal mode surround current line
          normal_line = "yS", -- Normal mode surround on new lines
          normal_cur_line = "ySS", -- Normal mode surround current line on new lines
          visual = "S", -- Visual mode surround
          visual_line = "gS", -- Visual mode surround on new lines
          delete = "ds", -- Delete surround
          change = "cs", -- Change surround
          change_line = "cS", -- Change surround with surround on new lines
        },
        -- Specify aliases for surroundings
        surrounds = {
          -- Custom text objects
          ["("] = { add = { "( ", " )" }, find = "(%b())", delete = "^(. ?)().-( ?.)()$" },
          ["{"] = { add = { "{ ", " }" }, find = "(%b{})", delete = "^(. ?)().-( ?.)()$" },
          ["<"] = { add = { "< ", " >" }, find = "(%b<>)", delete = "^(. ?)().-( ?.)()$" },
          ["["] = { add = { "[ ", " ]" }, find = "(%b[])", delete = "^(. ?)().-( ?.)()$" },
          -- Alias for function calls - ysaf
          ["f"] = {
            add = function()
              local fname = vim.fn.input("Function name: ")
              if fname ~= "" then
                return { { fname .. "(" }, { ")" } }
              end
            end,
            find = "%w+%b()",
            delete = "^(.-)().-()()$",
          },
          -- Markdown specific
          ["*"] = {
            add = { "*", "*" },
            find = "%*%b**%*",
            delete = "^(%*)().-(%*)()$",
          },
          ["_"] = {
            add = { "_", "_" },
            find = "%_%b__%_",
            delete = "^(%_)().-(%_)()$",
          },
          -- HTML comment
          ["c"] = {
            add = { "<!-- ", " -->" },
            find = "<%!%-%-%s.-%s%-%->",
            delete = "^(<%!%-%-%s)().-(%s%-%->)()$",
          },
        },
        -- Extra functionality
        aliases = {
          ["b"] = { ")", "]", "}", ">" }, -- All brackets
          ["q"] = { "'", '"', "`" }, -- All quotes
          ["s"] = { ")", "]", "}", ">", "'", '"', "`" }, -- All surround characters
        },
        -- Whether the cursor follows the right-hand side of the surrounding
        move_cursor = "begin",
        -- Whether to indent on surrounding (e.g., ysiw})
        indent_lines = true,
        -- Whether to highlight the surrounding during operation
        highlight = {
          duration = 1000,
        },
      },
      config = function(_, opts)
        require("nvim-surround").setup(opts)

        -- Additional surrounding utilities
        vim.api.nvim_create_user_command("WrapWith", function(args)
          local left = args.args:sub(1, 1)
          local right = args.args:sub(2, 2)
          if right == "" then
            -- If only one character is provided, use it for both sides
            right = left
          end

          -- Get visual selection positions
          local start_line, start_col = vim.fn.line("'<"), vim.fn.col("'<")
          local end_line, end_col = vim.fn.line("'>"), vim.fn.col("'>")

          -- Insert surrounding characters
          if start_line == end_line then
            -- Single line selection
            local line = vim.fn.getline(start_line)
            local new_line = line:sub(1, start_col - 1)
              .. left
              .. line:sub(start_col, end_col)
              .. right
              .. line:sub(end_col + 1)
            vim.fn.setline(start_line, new_line)
          else
            -- Multi-line selection
            -- Add right surround to the end line
            local end_line_text = vim.fn.getline(end_line)
            vim.fn.setline(end_line, end_line_text:sub(1, end_col) .. right .. end_line_text:sub(end_col + 1))

            -- Add left surround to the start line
            local start_line_text = vim.fn.getline(start_line)
            vim.fn.setline(start_line, start_line_text:sub(1, start_col - 1) .. left .. start_line_text:sub(start_col))
          end
        end, { nargs = 1, range = true, desc = "Wrap selection with characters" })

        -- Additional keymap for wrapping selection
        vim.keymap.set("v", "<leader>sw", ":WrapWith ", { desc = "Wrap selection with characters" })
      end,
    },

    -- Auto-pairs for automatic closing of brackets and quotes
    {
      "windwp/nvim-autopairs",
      event = "InsertEnter",
      dependencies = { "hrsh7th/nvim-cmp" },
      opts = {
        check_ts = true, -- Use treesitter to check for pairs
        ts_config = { -- Disable autopairs in specific contexts using treesitter
          lua = { "string", "comment" },
          javascript = { "string", "template_string", "comment" },
          python = { "string", "comment" },
        },
        disable_filetype = { "TelescopePrompt", "vim" }, -- Disable in these filetypes
        disable_in_macro = false, -- Still work in macros
        disable_in_visualblock = false, -- Still work in visual block mode
        ignored_next_char = string.gsub([[ [%w%%%'%[%"%.] ]], "%s+", ""), -- Don't add pairs if next char matches
        enable_moveright = true, -- Move past closing pairs
        enable_afterquote = true, -- Add pairs after quotes
        enable_check_bracket_line = true, -- Don't add pair if there's a closing bracket on the same line
        map_cr = true, -- Map the <CR> key
        map_bs = true, -- Map the <BS> key
        map_c_h = true, -- Map the <C-h> key
        map_c_w = true, -- Map the <C-w> key to delete a pair
        -- Fast wrap lets you surround existing text with a keybinding
        fast_wrap = {
          map = "<M-e>", -- Use Alt-e to trigger fast wrap
          chars = { "{", "[", "(", '"', "'" }, -- Characters that can be used for fast wrap
          pattern = [=[[%'%"%>%]%)%}%,]]=], -- Patterns after which fast wrap can be triggered
          end_key = "$", -- Key to place cursor at end of wrapped region
          keys = "qwertyuiopzxcvbnmasdfghjkl", -- Keys to choose position when wrapping
          check_comma = true, -- Check for a comma before appending a closing bracket
          highlight = "Search", -- Highlight for the virtual text
          highlight_grey = "Comment", -- Highlight for unused positions
        },
      },
      config = function(_, opts)
        -- Setup auto-pairs with the given options
        local npairs = require("nvim-autopairs")
        npairs.setup(opts)

        -- Make autopairs and completion work together
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        local cmp = require("cmp")
        cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())

        -- Configure rule for adding spaces between brackets
        local Rule = require("nvim-autopairs.rule")
        local brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } }

        -- Add space between brackets rule
        npairs.add_rules({
          Rule(" ", " "):with_pair(function(opts)
            local pair = opts.line:sub(opts.col - 1, opts.col)
            return vim.tbl_contains({
              brackets[1][1] .. brackets[1][2],
              brackets[2][1] .. brackets[2][2],
              brackets[3][1] .. brackets[3][2],
            }, pair)
          end),
        })

        -- Add space inside bracket pairs
        for _, bracket in pairs(brackets) do
          npairs.add_rules({
            Rule(bracket[1] .. " ", " " .. bracket[2])
              :with_pair(function()
                return false
              end)
              :with_move(function(opts)
                return opts.prev_char:match(".%" .. bracket[2]) ~= nil
              end)
              :use_key(bracket[2]),
          })
        end

        -- Add rules for HTML/JSX tag completion
        npairs.add_rules({
          Rule("<", ">"):with_pair(function()
            return vim.bo.filetype:match("^html")
              or vim.bo.filetype:match("jsx")
              or vim.bo.filetype:match("tsx")
              or vim.bo.filetype:match("svelte")
              or vim.bo.filetype:match("vue")
          end):with_cr(function()
            return true
          end),
        })
      end,
    },

    -- Add auto tag closing via TreeSitter
    {
      "windwp/nvim-ts-autotag",
      event = { "InsertEnter" },
      dependencies = { "nvim-treesitter/nvim-treesitter" },
      opts = {
        enable = true,
        enable_rename = true, -- Enable renaming tags
        enable_close = true, -- Enable closing tags
        enable_close_on_slash = true, -- Close tag when typing />
        filetypes = {
          "html",
          "xml",
          "jsx",
          "tsx",
          "javascript",
          "typescript",
          "javascriptreact",
          "typescriptreact",
          "svelte",
          "vue",
          "markdown",
        },
      },
    },

    -- Automatically add closing delimiters for functions and control structures
    {
      "ray-x/lsp_signature.nvim",
      event = { "InsertEnter" },
      opts = {
        bind = true, -- This is mandatory, otherwise border config won't get registered
        handler_opts = {
          border = "rounded", -- double, rounded, single, shadow, none
        },
        max_height = 12, -- max height of signature floating window
        max_width = 80, -- max width of signature floating window
        wrap = true, -- allow doc/signature wrap inside floating window
        floating_window = true, -- show hint in a floating window
        hint_enable = true, -- virtual hint enable
        hint_prefix = "🔍 ", -- Panda for parameter, NOTE: for the terminal not support emoji
        hint_scheme = "String",
        hi_parameter = "LspSignatureActiveParameter", -- how your parameter will be highlighted
        toggle_key = "<C-k>", -- Toggle signature on and off in insert mode
        select_signature_key = "<C-n>", -- cycle to next signature if multiple signatures exist
      },
    },
  }
end

return M
