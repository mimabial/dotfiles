--------------------------------------------------------------------------------
-- Language-Specific Configurations
--------------------------------------------------------------------------------
--
-- This module imports all language-specific configurations.
-- Each language gets its own file with dedicated plugins, settings, and tools.
--
-- The configuration is modular so you can:
-- 1. Add new languages by creating new files in this directory
-- 2. Disable languages by commenting out their imports
-- 3. Customize individual language setup without affecting others
--
-- Language support includes:
-- * Syntax highlighting (TreeSitter)
-- * LSP servers
-- * Formatters and linters
-- * Language-specific plugins
-- * Custom keymaps and snippets
-- * Testing and debugging integrations
--------------------------------------------------------------------------------

return {
  -- Web Development
  { import = "plugins.langs.web" }, -- JavaScript, TypeScript, HTML, CSS, etc.

  -- Systems Programming
  { import = "plugins.langs.rust" }, -- Rust
  { import = "plugins.langs.cpp" }, -- C/C++
  { import = "plugins.langs.go" }, -- Go

  -- Scripting Languages
  { import = "plugins.langs.python" }, -- Python
  { import = "plugins.langs.lua" }, -- Lua
  { import = "plugins.langs.bash" }, -- Shell/Bash

  -- JVM Languages
  { import = "plugins.langs.java" }, -- Java
  { import = "plugins.langs.kotlin" }, -- Kotlin

  -- Other Programming Languages
  { import = "plugins.langs.ruby" }, -- Ruby
  { import = "plugins.langs.php" }, -- PHP
  { import = "plugins.langs.elixir" }, -- Elixir

  -- Data Languages
  { import = "plugins.langs.sql" }, -- SQL Databases
  { import = "plugins.langs.json" }, -- JSON and YAML

  -- Documentation Languages
  { import = "plugins.langs.markdown" }, -- Markdown
  { import = "plugins.langs.latex" }, -- LaTeX

  -- Cloud & DevOps
  { import = "plugins.langs.devops" }, -- Docker, Terraform, Kubernetes, etc.

  -- Debugging Support
  {
    import = "plugins.tools.debug", -- Debug Adapter Protocol (DAP) setup
    enabled = true, -- Easily disable debugging if not needed
  },
}
