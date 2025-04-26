# NeoCode - Enhanced Neovim Configuration

A fully-featured, modular Neovim configuration designed to provide an IDE-like experience with intelligent code completion, diagnostics, formatting, and AI assistance for all major programming languages.

## Features

### 🧠 Intelligent Coding

- **LSP Integration**: Complete language server setup for 40+ languages
- **Rich Completions**: Context-aware suggestions with documentation
- **Code Actions**: Quick fixes, refactoring suggestions, and automated imports
- **Inlay Hints**: Type information and parameter names inline
- **Diagnostics**: Real-time error checking and linting
- **Snippets**: Expansive collection of language-specific snippets

### 🤖 AI Assistance

- **Codeium/Copilot Integration**: AI-powered code suggestions
- **Code Explanation**: Get explanation of complex code
- **Docstring Generation**: Auto-generate documentation
- **Code Transformation**: Convert code between languages or styles

### ✨ Code Quality

- **Automated Formatting**: Language-aware code formatting on save
- **Linting**: Static analysis tools for all major languages
- **Import Organization**: Automatic import sorting and removal of unused imports
- **Type Checking**: Integrated type verification for dynamically typed languages

### 🔍 Navigation

- **Fuzzy Finding**: Quick file and text search with Telescope
- **Symbol Browser**: Jump to functions, classes, and variables
- **File Explorer**: Multiple ways to browse project files
- **Buffer Management**: Efficient buffer navigation with tabs

### 🛠️ Development Tools

- **Git Integration**: Stage, commit, diff, and blame without leaving Neovim
- **Debugging**: Full debug adapter protocol support with breakpoints and inspection
- **Terminal**: Integrated terminal experience
- **Database Client**: Query and explore databases directly in Neovim

### 🎨 Beautiful Interface

- **Syntax Highlighting**: Tree-sitter based precise highlighting
- **Status Line**: Informative and customizable status line
- **Buffer Line**: Visual buffer tabs
- **Notifications**: Modern notification system
- **Modern UI**: Dashboard, select menus, and command palette

## Requirements

- Neovim >= 0.9.0
- Git
- A [Nerd Font](https://www.nerdfonts.com/) (optional but recommended)
- For some language servers:
  - Node.js >= 14.14
  - Python >= 3.6
  - Rust, Go, etc. (only for respective language support)

## Installation

1. Back up your existing Neovim configuration (if any):
   ```bash
   mv ~/.config/nvim ~/.config/nvim.bak
   ```

2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/neocode.git ~/.config/nvim
   ```

3. Start Neovim:
   ```bash
   nvim
   ```

4. Wait for plugins to install automatically
5. Run `:checkhealth` to verify your installation

## Language Support

This configuration provides full IDE-like features for 40+ languages, including:

| Language      | LSP           | Formatting       | Linting       | Debugging    | Snippets |
|---------------|---------------|------------------|---------------|--------------|----------|
| Python        | pyright       | black, isort     | flake8, mypy  | debugpy      | ✅      |
| JavaScript/TS | tsserver      | prettier, eslint | eslint        | vscode-js    | ✅      |
| Rust          | rust_analyzer | rustfmt          | clippy        | codelldb     | ✅      |
| Go            | gopls         | gofmt, goimports | golangci-lint | delve        | ✅      |
| Lua           | lua_ls        | stylua           | luacheck      | -            | ✅      |
| C/C++         | clangd        | clang-format     | clang-tidy    | codelldb     | ✅      |
| Java          | jdtls         | google-java-fmt  | checkstyle    | java-debug   | ✅      |
| ... and many more!

## Key Bindings

This configuration uses Space as the leader key. Here are some essential keybindings:

### General

- `<Space>` - Leader key
- `<Esc>` - Clear search highlights
- `jk` - Exit insert mode (alternative to Escape)

### Files and Navigation

- `<leader>ff` - Find files
- `<leader>fg` - Live grep (find text)
- `<leader>fb` - Browse buffers
- `<leader>fr` - Recent files
- `<leader>e` - Toggle file explorer
- `-` - Navigate up in file explorer

### Code Intelligence

- `gd` - Go to definition
- `gr` - Show references
- `K` - Show hover documentation
- `<leader>ca` - Code actions
- `<leader>rn` - Rename symbol
- `<leader>cf` - Format document
- `<leader>ch` - Toggle inlay hints

### AI Assistance

- `<leader>aa` - Generate AI completion
- `<leader>ae` - Explain code
- `<leader>ac` - Generate comment/docstring
- `<leader>ar` - Refactor with AI

### Git Operations

- `<leader>gg` - Open Git status
- `<leader>gd` - Git diff
- `<leader>gb` - Git blame
- `<leader>gc` - Git commit
- `]h` and `[h` - Next/previous Git hunk

### Windows and Tabs

- `<C-h/j/k/l>` - Navigate between windows
- `<leader>w-` - Split window horizontally
- `<leader>w|` - Split window vertically
- `<leader>wc` - Close window
- `<Tab>` and `<S-Tab>` - Next/previous buffer

## Customization

The configuration is designed to be easily customizable:

### User Settings

Add your personal settings to `lua/config/settings.lua`. This file won't be overwritten by updates.

### Adding Plugins

1. Create a new file in the appropriate subdirectory of `lua/plugins/`
2. Follow the lazy.nvim plugin spec format
3. Your plugins will be automatically loaded

### Language Configuration

To add or modify language support:

1. Edit the appropriate file in `lua/plugins/langs/`
2. Add language-specific settings, or create a new file for an unsupported language

## For More Information

See the comments in individual files for detailed explanations of how each component works.

- `init.lua` - The main entry point with loader logic
- `lua/core/` - Core Neovim settings
- `lua/plugins/` - Plugin configurations

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgements

This configuration builds upon the work of many Neovim plugin authors and configuration frameworks. Special thanks to all the plugin developers who make this possible.

## License

MIT
