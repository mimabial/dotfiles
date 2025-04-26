# NeoCode Documentation

## Configuration Architecture

NeoCode uses a modular, layered architecture to organize its components:

```
Core Layer → Plugin System → Feature Modules → Language Modules → User Settings
```

### Core Layer
The foundation of the configuration, handling Neovim's native settings, key mappings, and autocommands. This layer is simple but powerful, providing the base upon which everything else is built.

### Plugin System
Built on lazy.nvim for efficient plugin management with smart lazy loading. Plugins are organized into logical groups and loaded only when needed.

### Feature Modules
Self-contained feature sets (LSP, completions, debugging, etc.) that work together but can be understood independently.

### Language Modules
Language-specific configurations that extend the feature modules with language-specialized settings.

### User Settings
A separate area for your personal preferences that won't be overwritten by updates.

## How Components Interact

### LSP Integration Flow

1. **Server Detection**: When opening a file, the system identifies the filetype
2. **Server Activation**: The appropriate language server is launched by lspconfig
3. **Capability Registration**: LSP capabilities are registered with completion system
4. **UI Hookup**: Diagnostics, code actions, and hover information are connected to the UI
5. **Keybinding Activation**: Language-specific keybindings become available

The design ensures each component is loosely coupled but works seamlessly together.

### Completion System Architecture

The completion system uses a multi-source approach:

```
LSP → Snippets → AI Suggestions → Buffer → Path → Commands
```

Sources are prioritized, with LSP suggestions generally at the top, followed by snippets, AI completions, and context-based suggestions.

### Debugging Integration

The debugging system connects several components:

1. **DAP Core**: The base Debug Adapter Protocol implementation
2. **Language Adapters**: Language-specific debug adapters connected to the core
3. **UI Layer**: Visual representation of the debugging state
4. **Keybindings**: Consistent interface for controlling the debugger
5. **Test Integration**: Connection between test runners and debugging

## Customizing the Configuration

### Adding a New Language

To add support for a new language:

1. Create a new file in `lua/plugins/langs/` (e.g., `lua/plugins/langs/rust.lua`)
2. Configure the language using the template pattern from existing language files
3. Import the new file in `lua/plugins/langs/init.lua`

### Modifying LSP Settings

To customize LSP behavior for a language:

1. Locate the server in `lua/plugins/lsp/servers.lua`
2. Adjust the settings table for your specific needs
3. For deeper customization, modify `on_attach` function for that server

### Adding New Plugins

To add new plugins:

1. Determine the appropriate category (UI, tools, langs, etc.)
2. Add an entry in the corresponding file using lazy.nvim spec format
3. Configure the plugin with appropriate settings and keybindings

### Customizing Keybindings

The keybinding system uses a simple but powerful convention:

- `<leader>` is mapped to Space
- First letter after leader indicates category (f=files, b=buffers, etc.)
- Second letter indicates specific action

To modify keybindings:

1. Edit global keybindings in `lua/core/keymaps.lua`
2. Edit plugin-specific keybindings in their respective plugin files
3. Override any keybindings in your user settings

## Performance Tuning

NeoCode is designed to be responsive, but you can further optimize it:

1. **Selective Loading**: Disable language modules you don't use in `lua/plugins/langs/init.lua`
2. **LSP Minimization**: Adjust server options to reduce memory usage in `lua/plugins/lsp/servers.lua`
3. **Startup Optimization**: Use `:StartupTime` to identify and address slow plugins

## Troubleshooting

Common issues and solutions:

### LSP Not Working

1. Check server installation with `:Mason`
2. Verify filetype detection with `:echo &filetype`
3. Inspect LSP logs with `:LspLog`
4. Test server configuration with `:LspInfo`

### Slow Performance

1. Identify slow plugins with `:StartupTime`
2. Check for plugins that may conflict
3. Review event hooks that might cause delays
4. Disable heavy features temporarily to isolate issues

### Keybindings Not Working

1. Check for conflicts with `:verbose map <key>`
2. Verify plugin loading with `:Lazy`
3. Check leader key configuration
4. Test in a minimal configuration to isolate the issue

## Advanced Usage

### Creating Custom Commands

Add custom commands in your user settings:

```lua
vim.api.nvim_create_user_command("MyCommand", function()
  -- Command implementation
end, { desc = "My custom command" })
```

### Building Project-Specific Configurations

For project-specific settings, use `.nvim.lua` in your project root:

```lua
-- .nvim.lua in project root
vim.g.my_project_setting = true

-- Configure formatters for this project
vim.b.disable_autoformat = false
```

### Extending the AI Assistant

To enhance the AI assistant:

1. Add custom prompts in `lua/plugins/coding/ai.lua`
2. Configure new keybindings for specific AI tasks
3. Connect with external AI services if needed

## Getting Help

- Use `:help` to access Neovim's built-in documentation
- Press `<leader>?` to see all keybindings
- Check `:checkhealth` for system diagnostics
- Visit the GitHub repository for updates and issues

## Keeping Updated

To update your configuration:

1. Pull the latest changes from the repository
2. Run `:Lazy sync` to update plugins
3. Check `:checkhealth` to verify everything is working
4. Review the changelog for breaking changes

This configuration will continue to evolve with Neovim and the plugin ecosystem, bringing you the best development experience possible while maintaining the efficiency and power of Vim.
