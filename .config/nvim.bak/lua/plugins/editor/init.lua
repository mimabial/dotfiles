-- Editor enhancements initialization
-- This file loads all editor feature plugins

return {
  -- Import all editor enhancement configurations
  { import = "plugins.editor.navigation" },
  { import = "plugins.editor.text-objects" },
  { import = "plugins.editor.comments" },
  { import = "plugins.editor.surround" },
  { import = "plugins.editor.autopairs" },
  { import = "plugins.editor.search" },
  { import = "plugins.editor.keymaps" },
  { import = "plugins.editor.sessions" },
}
