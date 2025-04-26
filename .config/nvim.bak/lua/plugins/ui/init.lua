-- UI components initialization
-- This file loads all UI-related plugins and configurations

return {
  -- Import all UI component configurations
  { import = "plugins.ui.colorscheme" },
  { import = "plugins.ui.statusline" },
  { import = "plugins.ui.dashboard" },
  { import = "plugins.ui.notifications" },
  { import = "plugins.ui.explorer" },
  { import = "plugins.ui.bufferline" },
  { import = "plugins.ui.indentline" },
}
