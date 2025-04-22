return {
    "akinsho/bufferline.nvim",
    enabled = true,
    -- dir = "~/personal/bufferline.nvim",
    event = "VimEnter",
    keys = function()
      -- stylua: ignore
      local keys = {
        { "<leader>bp",        "<cmd>BufferLineTogglePin<cr>",                       desc = "Toggle pin", },
        { "<M-m>",             "<cmd>BufferLineTogglePin<cr>",                       desc = "Toggle pin", },
        { "<leader>bP",        "<cmd>BufferLineGroupClose ungrouped<cr>",            desc = "Delete non-pinned buffers", },
        { "<leader><leader>o", "<cmd>BufferLineCloseOthers<cr>",                     desc = "Delete other buffers", },
        { "<leader>br",        "<cmd>BufferLineCloseRight<cr>",                      desc = "Delete buffers to the right", },
        { "<leader>bl",        "<cmd>BufferLineCloseLeft<cr>",                       desc = "Delete buffers to the left", },
        { "[b",                "<cmd>BufferLineCyclePrev<cr>",                       desc = "Prev buffer", },
        { "]b",                "<cmd>BufferLineCycleNext<cr>",                       desc = "Next buffer", },
        --
        { "<leader>dL",        "<cmd>BufferLineCloseRight<cr>",                      desc = "Delete buffers to the right", },
        { "<leader>dH",        "<cmd>BufferLineCloseLeft<cr>",                       desc = "Delete buffers to the left", },
        { "<M-[>",             "<cmd>BufferLineCyclePrev<cr>",                       desc = "Prev buffer", },
        { "<M-]>",             "<cmd>BufferLineCycleNext<cr>",                       desc = "Next buffer", },
        { "<M-S-]>",           "<cmd>BufferLineMoveNext<cr>",                        desc = "Move buffer to Next", },
        { "<M-S-[>",           "<cmd>BufferLineMovePrev<cr>",                        desc = "Move buffer to Previous", },
        { "<M-S-0>",           "<cmd>lua require'bufferline'.move_to(1)<cr>",        desc = "Move buffer to first", },
        { "<M-S-4>",           "<cmd>lua require'bufferline'.move_to(-1)<cr>",       desc = "Move buffer to last", },
        { "<M-9>",             "<cmd>lua require('bufferline').go_to(-1, true)<cr>", desc = "Go to last buffer", },
        { "<leader>9",         "<cmd>lua require('bufferline').go_to(-1, true)<cr>", desc = "Go to last buffer", },
      }
      for i = 1, 8 do
        table.insert(keys, {
          "<leader>" .. i,
          "<cmd>lua require('bufferline').go_to(" .. i .. ", true)<cr>",
          desc = "Go to buffer " .. i,
        })
        table.insert(keys, {
          "<M-" .. i .. ">",
          "<cmd>lua require('bufferline').go_to(" .. i .. ", true)<cr>",
          desc = "Go to buffer " .. i,
          mode = { "n", "v", "i" },
        })
      end
      -- print(vim.inspect(keys))
      return keys
    end,
    opts = function()
      -- local colors = require("base16-colorscheme").colors
      -- local colors = require("colors.tokyodark-terminal")
      vim.api.nvim_set_hl(0, "MyBufferSelected", { fg = vim.g.base16_gui00, bg = vim.g.base16_gui09, bold = true })
      -- vim.api.nvim_set_hl(0, 'MyHarpoonSelected', { fg = colors.base01, bg = colors.base0B })
      return {
        highlights = {
          buffer_selected = { link = "MyBufferSelected" },
          numbers_selected = { link = "MyBufferSelected" },
          tab_selected = { link = "MyBufferSelected" },
          modified_selected = { link = "MyBufferSelected" },
          duplicate_selected = { link = "MyBufferSelected" },
        },
        options = {
          dispatch_update_events = true,
          -- numbers = 'ordinal',
          numbers = function(opts)
            local state = require("bufferline.state")
            for i, buf in ipairs(state.components) do
              if buf.id == opts.id then
                return i
              end
            end
            return opts.ordinal
          end,
          close_command = function(n)
            require("mini.bufremove").delete(n, false)
          end,
          right_mouse_command = function(n)
            require("mini.bufremove").delete(n, false)
          end,
          diagnostics = false,
          -- diagnostics = "coc",
          -- always_show_bufferline = false,
          show_close_icon = false,
          show_buffer_close_icons = false,
          show_buffer_icons = false,
          indicator = { style = "none" },
          separator_style = { "", "" },
          offsets = {
            {
              filetype = "coc-explorer",
              text = "File Explorer",
              highlight = "Directory",
              text_align = "left",
            },
            {
              filetype = "neo-tree",
              text = "Neo-tree",
              highlight = "Directory",
              text_align = "left",
            },
          },
        },
      }
    end,
    config = function(_, opts)
      require("bufferline").setup(opts)
      -- Fix bufferline when restoring a session
      -- print(vim.inspect(require('bufferline.state')))
      vim.api.nvim_create_autocmd("BufAdd", {
        callback = function()
          vim.schedule(function()
            pcall(nvim_bufferline)
          end)
        end,
      })
    end,
  },