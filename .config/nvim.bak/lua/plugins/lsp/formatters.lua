--------------------------------------------------------------------------------
-- Formatters Configuration
--------------------------------------------------------------------------------
--
-- This module configures code formatters for different languages.
-- We use null-ls to integrate formatters that don't have Language Server Protocol
-- support directly.
--
-- Each formatter is configured with:
-- 1. The file types it supports
-- 2. Any special configuration it needs
-- 3. Any command-line arguments to customize behavior
--
-- To add a new formatter:
-- 1. Check if it's available in none-ls.builtins.formatting
-- 2. Add it to the sources list with any required configuration
--------------------------------------------------------------------------------

local M = {}

local null_ls = require("none-ls")
local formatting = null_ls.builtins.formatting

-- List of all formatter sources
M.sources = {
  --------------------------------------------------------------------------------
  -- General Purpose Formatters
  --------------------------------------------------------------------------------

  -- Prettier for web development files
  formatting.prettier.with({
    -- Recognize more file types than the default
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
      "svelte",
      "css",
      "scss",
      "less",
      "html",
      "json",
      "jsonc",
      "yaml",
      "markdown",
      "markdown.mdx",
      "graphql",
      "handlebars",
    },
    extra_args = { "--prose-wrap", "always" },
    prefer_local = "node_modules/.bin", -- Use local project version of prettier if available
  }),

  --------------------------------------------------------------------------------
  -- Language Specific Formatters
  --------------------------------------------------------------------------------

  -- Lua
  formatting.stylua.with({
    condition = function(utils)
      -- Only use if stylua.toml or .stylua.toml exists
      return utils.root_has_file({ "stylua.toml", ".stylua.toml" })
    end,
    extra_args = { "--indent-type", "Spaces", "--indent-width", "2" },
  }),

  -- Python
  formatting.black.with({
    extra_args = { "--line-length", "88", "--preview" },
    prefer_local = ".venv/bin", -- Use local virtual environment if available
  }),
  formatting.isort.with({
    extra_args = { "--profile", "black" },
    prefer_local = ".venv/bin",
  }),
  formatting.ruff.with({
    extra_args = { "--fix" },
    prefer_local = ".venv/bin",
  }),

  -- Shell
  formatting.shfmt.with({
    extra_args = { "-i", "2", "-ci", "-bn" },
  }),

  -- Rust
  formatting.rustfmt.with({
    extra_args = { "--edition", "2021" },
  }),

  -- Go
  formatting.gofmt,
  formatting.goimports,

  -- C/C++/Java etc.
  formatting.clang_format.with({
    filetypes = { "c", "cpp", "cs", "java", "cuda", "proto" },
    extra_args = { "-style=file:.clang-format" },
  }),

  -- Web development
  formatting.prettierd.with({ -- Daemon version of prettier (faster)
    condition = function(utils)
      return utils.has_exec("prettierd")
    end,
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
      "svelte",
      "css",
      "scss",
      "less",
      "html",
      "json",
      "jsonc",
      "yaml",
      "markdown",
      "markdown.mdx",
      "graphql",
      "handlebars",
    },
  }),

  -- JSON & YAML with schema validation
  formatting.fixjson,
  formatting.yamlfmt,

  -- SQL
  formatting.sql_formatter.with({
    extra_args = { "--language", "postgresql" },
  }),

  -- XML/HTML
  formatting.xmlformat,
  formatting.djlint.with({
    filetypes = { "html", "htmldjango", "jinja", "jinja.html" },
  }),

  -- Markdown/Text
  formatting.markdownlint,
  formatting.cbfmt.with({
    filetypes = { "markdown" },
  }),

  -- PHP
  formatting.phpcbf,

  -- Ruby
  formatting.rubocop,

  -- XML
  formatting.xmllint,

  -- Elixir
  formatting.mix,
}

--------------------------------------------------------------------------------
-- Functions to manually format code
--------------------------------------------------------------------------------

-- Format the current buffer using available formatters
function M.format_buffer()
  vim.lsp.buf.format({
    async = true,
    timeout_ms = 2000,
  })
end

-- Format a visual selection using available formatters
function M.format_range()
  vim.lsp.buf.format({
    async = true,
    timeout_ms = 2000,
    range = {
      ["start"] = vim.api.nvim_buf_get_mark(0, "<"),
      ["end"] = vim.api.nvim_buf_get_mark(0, ">"),
    },
  })
end

return M
