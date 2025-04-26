-- ~/.config/nvim/lua/core/utils.lua
-- Utility functions

local M = {}

-- Load a module without errors
---@param module string The module to require
---@return any|nil The loaded module or nil if an error occurred
function M.safe_require(module)
  local ok, result = pcall(require, module)
  if not ok then
    vim.notify("Error loading module: " .. module, vim.log.levels.ERROR)
    return nil
  end
  return result
end

-- Toggle a boolean option
---@param option string The option to toggle
function M.toggle_option(option)
  local value = not vim.api.nvim_get_option_value(option, {})
  vim.api.nvim_set_option_value(option, value, {})
  vim.notify(option .. " set to " .. tostring(value), vim.log.levels.INFO)
end

-- Get a color value from the current colorscheme
---@param name string The name of the highlight group
---@param attribute string The attribute to get (e.g., "fg", "bg")
---@return string The color in hex format or an empty string
function M.get_color(name, attribute)
  local color = vim.api.nvim_get_hl(0, { name = name })
  if not color then
    return ""
  end

  local value = color[attribute]
  if not value then
    return ""
  end

  -- Convert decimal to hex
  return string.format("#%06x", value)
end

-- Format a buffer using available formatters
---@param bufnr number|nil The buffer number, or current buffer if nil
---@param async boolean|nil Whether to format asynchronously
function M.format_buffer(bufnr, async)
  bufnr = bufnr or 0
  async = async == nil and false or async

  -- Try LSP formatting first
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client.server_capabilities.documentFormattingProvider then
      vim.lsp.buf.format({
        bufnr = bufnr,
        async = async,
        filter = function(c)
          return c.id == client.id
        end,
      })
      return
    end
  end

  -- Fallback to other formatters like conform.nvim or null-ls if available
  local has_conform, conform = pcall(require, "conform")
  if has_conform then
    conform.format({ bufnr = bufnr, async = async, lsp_fallback = false })
    return
  end

  -- Second fallback to null-ls
  local has_null_ls, null_ls = pcall(require, "null-ls")
  if has_null_ls and null_ls.is_registered({ method = null_ls.methods.FORMATTING }) then
    vim.lsp.buf.format({
      bufnr = bufnr,
      async = async,
      filter = function(client)
        return client.name == "null-ls"
      end,
    })
    return
  end

  -- No formatter available
  vim.notify("No formatter available for this buffer", vim.log.levels.WARN)
end

-- Create a floating window with a title
---@param opts table Options for the floating window
---@return number, number The window and buffer handles
function M.create_float(opts)
  opts = opts or {}
  local default_opts = {
    relative = "editor",
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.8),
    row = math.floor(vim.o.lines * 0.1),
    col = math.floor(vim.o.columns * 0.1),
    style = "minimal",
    border = "rounded",
    title = opts.title or "",
    title_pos = "center",
  }

  -- Merge options
  for k, v in pairs(opts) do
    default_opts[k] = v
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, default_opts)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Set window options
  vim.api.nvim_win_set_option(win, "winblend", 0)
  vim.api.nvim_win_set_option(win, "cursorline", true)

  -- Close with 'q'
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })

  return win, buf
end

-- Get an icon for a filetype
---@param filetype string The filetype
---@return string, string The icon and its highlight group
function M.get_icon(filetype)
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    local icon, hl = devicons.get_icon_by_filetype(filetype)
    return icon or "", hl or ""
  end
  return "", ""
end

-- Terminal navigation helper for tmux navigation
---@param direction string The direction to navigate ('h', 'j', 'k', 'l')
---@return function A function that handles the navigation
function M.term_nav(direction)
  return function()
    if vim.fn.winnr() > 1 then
      vim.cmd("wincmd " .. direction)
    else
      vim.fn.system("tmux select-pane -" .. ({ h = "L", j = "D", k = "U", l = "R" })[direction])
    end
    return ""
  end
end

-- Wrap a function to be debounced (called only after delay without subsequent calls)
---@param ms number Delay in milliseconds
---@param fn function The function to debounce
---@return function The debounced function
function M.debounce(ms, fn)
  local timer = vim.loop.new_timer()
  return function(...)
    local args = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(args))
    end)
  end
end

-- Check if a path exists
---@param path string The path to check
---@return boolean Whether the path exists
function M.path_exists(path)
  return vim.loop.fs_stat(path) ~= nil
end

return M
