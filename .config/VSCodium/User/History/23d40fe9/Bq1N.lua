return {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      vim.g.lualine_laststatus = vim.o.laststatus
      if vim.fn.argc(-1) > 0 then
        -- set an empty statusline till lualine loads
        vim.o.statusline = " "
      else
        -- hide the statusline on the starter page
        vim.o.laststatus = 0
      end
      -- vim.highlight.create('LualineSelected',)
    end,
    opts = function()
      -- PERF: we don't need this lualine require madness 🤷
      local lualine_require = require("lualine_require")
      lualine_require.require = require

      local icons = require("lazyvim.config").icons
      vim.o.laststatus = vim.g.lualine_laststatus

      return {
        options = {
          theme = "auto",
          component_separators = { left = "|", right = "|" },
          section_separators = { left = " ", right = " " },
          globalstatus = true,
          disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch" },
          lualine_c = {
            {
              function()
                local cwd = vim.fn.getcwd()
                local p = vim.g.project_path
                if cwd == p then
                  return "󱂵  " .. vim.fs.basename(p)
                end
                return "󱂵 " .. vim.fs.basename(p) .. " 󱉭 " .. vim.fs.basename(cwd)
              end,
              { fg = Snacks.util.color("special") }
            },
            {
              "filetype",
              icon_only = true,
              separator = "",
              padding = {
                left = 1,
                right = 0,
              },
            },
            -- coc current function
            {
              function()
                return vim.b["coc_current_package"] or ""
              end,
            },
            {
              function(self)
                local path = vim.fn.expand("%:p")
                if path == "" then
                  return ""
                end
                local pp = vim.g.project_path
                if path:find(pp, 1, true) == 1 then
                  path = path:sub(#pp + 2)
                end
                if path:find(vim.fn.expand("~"), 1, true) == 1 then
                  path = path:gsub(vim.fn.expand("~"), "~", 1)
                end
                path = path:gsub("%%", "%%%%")
                local sep = package.config:sub(1, 1)
                local parts = vim.split(path, "[\\/]")
                if #parts > 3 then
                  parts = { parts[1], "…", parts[#parts - 1], parts[#parts] }
                end
                if vim.bo.modified then
                  parts[#parts] = LazyVim.lualine.format(self, parts[#parts], "Constant")
                end
                return table.concat(parts, sep)
              end,
            },
            {
              function()
                return vim.b["coc_current_function"] or ""
              end,
            },
            { "g:coc_status" },
          },
          lualine_x = {
              -- stylua: ignore
            {
              function() return require("noice").api.status.mode.get() end,
              cond = function() return package.loaded["noice"] and require("noice").api.status.mode.has() end,
              { fg = Snacks.util.color("Constant") },
            },
            -- stylua: ignore
            {
              function() return "  " .. require("dap").status() end,
              cond = function()
                return package.loaded["dap"] and
                    require("dap").status() ~= ""
              end,
              { fg = Snacks.util.color("Debug") }
            },
            {
              "diagnostics",
              symbols = {
                error = icons.diagnostics.Error,
                warn = icons.diagnostics.Warn,
                info = icons.diagnostics.Info,
                hint = icons.diagnostics.Hint,
              },
            },
            {
              require("lazy.status").updates,
              cond = require("lazy.status").has_updates,
              { fg = Snacks.util.color("special") }
            },
            {
              "diff",
              symbols = {
                added = icons.git.added,
                modified = icons.git.modified,
                removed = icons.git.removed,
              },
              source = function()
                local gitsigns = vim.b.gitsigns_status_dict
                if gitsigns then
                  return {
                    added = gitsigns.added,
                    modified = gitsigns.changed,
                    removed = gitsigns.removed,
                  }
                end
              end,
            },
          },
          lualine_y = {
            { "progress", separator = " ", padding = { left = 1, right = 0 } },
          },
          lualine_z = {
            { "location", padding = { left = 1, right = 1 } },
          },
        },
        extensions = { "lazy", "quickfix" },
      }
    end,
  },