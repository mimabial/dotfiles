--------------------------------------------------------------------------------
-- LSP Keymaps
--------------------------------------------------------------------------------
--
-- This module defines keymappings for working with LSP features.
--
-- The mappings are organized by functionality:
-- * Navigation (definitions, references, etc.)
-- * Information (hover, signature, etc.)
-- * Code modification (rename, code actions, etc.)
-- * Diagnostics (errors, warnings, etc.)
-- * Workspace (folders, symbols, etc.)
--
-- These keymaps are applied to buffers when an LSP server attaches.
--------------------------------------------------------------------------------

local M = {}

-- Applies keymaps when an LSP attaches to a buffer
---@param client table The LSP client
---@param bufnr number The buffer number
function M.on_attach(client, bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Helper function for setting keymaps
  local function map(mode, lhs, rhs, desc)
    opts.desc = desc
    vim.keymap.set(mode, lhs, rhs, opts)
  end

  --------------------------------------------------------------------------------
  -- Navigation (definitions, references, etc.)
  --------------------------------------------------------------------------------

  -- Go to definition, declaration, type definition, and implementation
  map("n", "gd", vim.lsp.buf.definition, "Go to Definition")
  map("n", "gD", vim.lsp.buf.declaration, "Go to Declaration")
  map("n", "gy", vim.lsp.buf.type_definition, "Go to Type Definition")
  map("n", "gi", vim.lsp.buf.implementation, "Go to Implementation")

  -- Find references to symbol under cursor
  map("n", "gr", vim.lsp.buf.references, "Go to References")

  -- Jump to the next/previous diagnostic in the buffer
  map("n", "]d", vim.diagnostic.goto_next, "Next Diagnostic")
  map("n", "[d", vim.diagnostic.goto_prev, "Previous Diagnostic")

  -- Jump to the next/previous error specifically
  map("n", "]e", function()
    vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR })
  end, "Next Error")

  map("n", "[e", function()
    vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR })
  end, "Previous Error")

  -- Jump to the next/previous warning
  map("n", "]w", function()
    vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN })
  end, "Next Warning")

  map("n", "[w", function()
    vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.WARN })
  end, "Previous Warning")

  --------------------------------------------------------------------------------
  -- Information (hover, signature, etc.)
  --------------------------------------------------------------------------------

  -- Show documentation for what is under cursor
  map("n", "K", vim.lsp.buf.hover, "Show Hover Documentation")

  -- Show signature help (parameter info)
  map("n", "<C-k>", vim.lsp.buf.signature_help, "Show Signature Help")
  map("i", "<C-k>", vim.lsp.buf.signature_help, "Show Signature Help")

  -- Toggle inlay hints (if available - Neovim 0.10+)
  if vim.lsp.inlay_hint then
    map("n", "<leader>lh", function()
      local current = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
      vim.lsp.inlay_hint.enable(bufnr, not current)
      vim.notify("Inlay hints " .. (not current and "enabled" or "disabled"), vim.log.levels.INFO)
    end, "Toggle Inlay Hints")
  end

  -- Show diagnostics in hover window
  map("n", "<leader>ld", function()
    vim.diagnostic.open_float({ border = "rounded" })
  end, "Show Diagnostics")

  --------------------------------------------------------------------------------
  -- Code modification (rename, code actions, etc.)
  --------------------------------------------------------------------------------

  -- Rename symbol under cursor
  map("n", "<leader>rn", vim.lsp.buf.rename, "Rename Symbol")

  -- Code actions (organize imports, fix errors, etc.)
  map("n", "<leader>ca", vim.lsp.buf.code_action, "Code Actions")
  map("v", "<leader>ca", vim.lsp.buf.code_action, "Code Actions (Range)")

  -- Format document
  if client.server_capabilities.documentFormattingProvider then
    map("n", "<leader>cf", function()
      vim.lsp.buf.format({ async = true })
      vim.notify("Formatted document", vim.log.levels.INFO)
    end, "Format Document")
  end

  -- Format selection
  if client.server_capabilities.documentRangeFormattingProvider then
    map("v", "<leader>cf", function()
      vim.lsp.buf.format({ async = true })
      vim.notify("Formatted selection", vim.log.levels.INFO)
    end, "Format Selection")
  end

  --------------------------------------------------------------------------------
  -- Diagnostics (errors, warnings, etc.)
  --------------------------------------------------------------------------------

  -- Show all diagnostics in the current buffer in a list
  map("n", "<leader>xx", "<cmd>Trouble document_diagnostics<cr>", "Document Diagnostics (Trouble)")

  -- Show all diagnostics in the workspace in a list
  map("n", "<leader>xX", "<cmd>Trouble workspace_diagnostics<cr>", "Workspace Diagnostics (Trouble)")

  -- Toggle diagnostics display on/off (useful when diagnostics are distracting)
  map("n", "<leader>xt", function()
    local current = vim.diagnostic.is_disabled({ bufnr = bufnr })
    if current then
      vim.diagnostic.enable(bufnr)
      vim.notify("Diagnostics enabled", vim.log.levels.INFO)
    else
      vim.diagnostic.disable(bufnr)
      vim.notify("Diagnostics disabled", vim.log.levels.INFO)
    end
  end, "Toggle Diagnostics")

  --------------------------------------------------------------------------------
  -- Workspace (folders, symbols, etc.)
  --------------------------------------------------------------------------------

  -- List all symbols in document
  map("n", "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", "Document Symbols")

  -- List all symbols in workspace
  map("n", "<leader>lS", "<cmd>Telescope lsp_workspace_symbols<cr>", "Workspace Symbols")

  -- Show symbol outline (sidebar with document structure)
  map("n", "<leader>lo", "<cmd>SymbolsOutline<cr>", "Symbols Outline")

  -- List references to symbol under cursor
  map("n", "<leader>lr", "<cmd>Telescope lsp_references<cr>", "References")

  -- Add workspace folder
  map("n", "<leader>la", vim.lsp.buf.add_workspace_folder, "Add Workspace Folder")

  -- Remove workspace folder
  map("n", "<leader>lR", vim.lsp.buf.remove_workspace_folder, "Remove Workspace Folder")

  -- List workspace folders
  map("n", "<leader>ll", function()
    vim.notify("Workspace folders: " .. vim.inspect(vim.lsp.buf.list_workspace_folders()), vim.log.levels.INFO)
  end, "List Workspace Folders")

  --------------------------------------------------------------------------------
  -- LSP Information
  --------------------------------------------------------------------------------

  -- Show info about LSP clients attached to the current buffer
  map("n", "<leader>li", "<cmd>LspInfo<cr>", "LSP Info")

  -- Show Mason (installer) UI
  map("n", "<leader>lm", "<cmd>Mason<cr>", "LSP Installer (Mason)")
end

return M
