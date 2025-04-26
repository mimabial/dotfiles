--------------------------------------------------------------------------------
-- Linters Configuration
--------------------------------------------------------------------------------
--
-- This module configures code linters for different languages.
-- Linters analyze code for potential errors, bugs, stylistic errors, and
-- suspicious constructs.
--
-- We use null-ls to integrate linters that don't have Language Server Protocol
-- support directly.
--
-- Each linter is configured with:
-- 1. The file types it supports
-- 2. Any special configuration it needs
-- 3. Any command-line arguments to customize behavior
--
-- To add a new linter:
-- 1. Check if it's available in none-ls.builtins.diagnostics
-- 2. Add it to the sources list with any required configuration
--------------------------------------------------------------------------------

local M = {}

local null_ls = require("none-ls")
local diagnostics = null_ls.builtins.diagnostics
local code_actions = null_ls.builtins.code_actions

-- List of all linter sources
M.sources = {
  --------------------------------------------------------------------------------
  -- General Purpose Linters
  --------------------------------------------------------------------------------

  -- Vale for prose linting (markdown, text)
  diagnostics.vale.with({
    filetypes = { "markdown", "text", "tex", "asciidoc" },
  }),

  -- Write-good for English text improvement suggestions
  diagnostics.write_good.with({
    filetypes = { "markdown", "text" },
    args = { "--no-passive" },
  }),

  -- Codespell for common spelling errors in code
  diagnostics.codespell.with({
    filetypes = {
      "javascript",
      "typescript",
      "python",
      "lua",
      "rust",
      "go",
      "c",
      "cpp",
      "java",
      "php",
      "ruby",
      "markdown",
      "text",
    },
    args = { "--builtin", "clear,rare,code", "-" },
  }),

  --------------------------------------------------------------------------------
  -- Language Specific Linters
  --------------------------------------------------------------------------------

  -- Lua
  diagnostics.luacheck.with({
    extra_args = { "--globals", "vim", "--no-max-line-length" },
  }),

  -- Python
  diagnostics.flake8.with({
    extra_args = { "--max-line-length", "88", "--extend-ignore", "E203" },
    prefer_local = ".venv/bin", -- Use local virtual environment if available
  }),
  diagnostics.mypy.with({
    prefer_local = ".venv/bin", -- Use local virtual environment if available
  }),
  diagnostics.pydocstyle.with({
    prefer_local = ".venv/bin", -- Use local virtual environment if available
  }),

  -- Shell
  diagnostics.shellcheck.with({
    diagnostics_format = "#{m} [#{c}]",
    filetypes = { "sh", "bash", "zsh" },
  }),

  -- JavaScript/TypeScript
  diagnostics.eslint_d.with({
    condition = function(utils)
      return utils.root_has_file({
        ".eslintrc.js",
        ".eslintrc.cjs",
        ".eslintrc.yaml",
        ".eslintrc.yml",
        ".eslintrc.json",
        ".eslintrc",
      })
    end,
    prefer_local = "node_modules/.bin", -- Use local project version if available
  }),

  -- JSON
  diagnostics.jsonlint,

  -- YAML
  diagnostics.yamllint,

  -- Terraform
  diagnostics.terraform_validate,
  diagnostics.tfsec,

  -- HTML
  diagnostics.tidy.with({
    filetypes = { "html", "xml" },
  }),

  -- Docker
  diagnostics.hadolint,

  -- SQL
  diagnostics.sqlfluff.with({
    extra_args = { "--dialect", "postgres" }, -- Change based on your SQL dialect
  }),

  -- Markdown
  diagnostics.markdownlint.with({
    extra_args = { "--config", ".markdownlint.json" },
  }),

  -- PHP
  diagnostics.php.with({
    prefer_local = "vendor/bin", -- Use local composer dependencies if available
  }),

  -- Go
  diagnostics.golangci_lint.with({
    args = {
      "run",
      "--out-format=json",
      "--fix=false", -- Set to true to auto-fix issues
      "$DIRNAME",
      "--path-prefix",
      "$ROOT",
    },
  }),

  -- Rust
  diagnostics.rustfmt.with({
    extra_args = { "--check" },
  }),

  --------------------------------------------------------------------------------
  -- Code Actions (Quick fixes and suggestions)
  --------------------------------------------------------------------------------

  -- Git related actions
  code_actions.gitsigns,

  -- ESLint fixes
  code_actions.eslint_d.with({
    prefer_local = "node_modules/.bin",
  }),

  -- ShellCheck fixes
  code_actions.shellcheck,

  -- Refactoring actions for dynamically typed languages
  code_actions.refactoring,

  -- Spelling fixes
  code_actions.proselint,
  code_actions.codespell,

  -- Practical extracting and inline refactoring actions
  code_actions.impl.with({
    prefer_local = ".venv/bin",
  }),
}

return M
