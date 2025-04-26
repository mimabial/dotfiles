--------------------------------------------------------------------------------
-- LSP Server Configurations
--------------------------------------------------------------------------------
--
-- This module defines the configuration for all language servers.
-- Each server can have custom settings while sharing common capabilities.
--
-- Structure:
-- 1. List of servers to install automatically
-- 2. Server-specific settings for each LSP
--
-- Add new language servers:
-- 1. Add the server name to ensure_installed list
-- 2. Add server settings to the settings table
--
-- See :help lspconfig-server-configurations for available servers and options
--------------------------------------------------------------------------------

local M = {}

-- List of LSP servers to install automatically with Mason
-- These will be set up with the default or custom settings below
M.ensure_installed = {
  -- Common Languages
  "lua_ls",      -- Lua
  "pyright",     -- Python
  "ruff_lsp",    -- Python linting/formatting
  "tsserver",    -- TypeScript/JavaScript
  "jsonls",      -- JSON
  "yamlls",      -- YAML
  "html",        -- HTML
  "cssls",       -- CSS
  
  -- Web Development
  "eslint",      -- ESLint
  "tailwindcss", -- Tailwind CSS
  "volar",       -- Vue
  "astro",       -- Astro
  "emmet_ls",    -- Emmet
  "graphql",     -- GraphQL
  "prismals",    -- Prisma ORM
  "svelte",      -- Svelte
  "angularls",   -- Angular
  
  -- Systems Programming
  "clangd",      -- C/C++
  "rust_analyzer", -- Rust
  "gopls",       -- Go
  "zls",         -- Zig
  
  -- JVM Languages
  "jdtls",       -- Java
  "kotlin_language_server", -- Kotlin
  "groovyls",    -- Groovy
  "lemminx",     -- XML
  
  -- Scripting Languages
  "bashls",      -- Bash
  "powershell_es", -- PowerShell
  
  -- Data Science & ML
  "pyright",     -- Python
  "r_language_server", -- R
  "julials",     -- Julia
  
  -- Cloud & DevOps
  "dockerls",    -- Docker
  "docker_compose_language_service", -- Docker Compose
  "terraformls", -- Terraform
  "helm_ls",     -- Helm
  "ansiblels",   -- Ansible
  "awk_ls",      -- AWK
  
  -- Databases
  "sqlls",       -- SQL
  
  -- Markup/Documentation
  "marksman",    -- Markdown
  "ltex",        -- LaTeX/Text
  "taplo",       -- TOML
  
  -- Other Languages
  "elixirls",    -- Elixir
  "phpactor",    -- PHP
  "ruby_ls",     -- Ruby
  "crystalline", -- Crystal
  "ocamllsp",    -- OCaml
  "hls",         -- Haskell
  "dartls",      -- Dart
  "denols",      -- Deno
  "typos_lsp",   -- Spelling
}

-- LSP Server specific configurations
-- Each server can have custom settings
M.settings = {
  -- Lua
  lua_ls = {
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT",
        },
        diagnostics = {
          globals = { "vim" },  -- Recognize vim global in Neovim config
        },
        workspace = {
          library = {
            vim.fn.expand("$VIMRUNTIME/lua"),
            vim.fn.stdpath("config") .. "/lua",
          },
          -- Don't prompt about third-party dependencies
          checkThirdParty = false,
        },
        telemetry = {
          enable = false,  -- Disable telemetry
        },
        completion = {
          callSnippet = "Replace",  -- Show function call snippets
        },
        hint = {  -- Inlay hints (Neovim 0.10+)
          enable = true,
          setType = true,
          paramType = true,
          paramName = "Literal",
          semicolon = "Disable",
          arrayIndex = "Enable",
        },
      },
    },
  },
  
  -- Python
  pyright = {
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          useLibraryCodeForTypes = true,
          typeCheckingMode = "basic",  -- Choose from: off, basic, strict
          inlayHints = {
            variableTypes = true,
            functionReturnTypes = true,
            parameterTypes = true,
          },
        },
      },
    },
  },
  
  -- Python (additional linting with ruff)
  ruff_lsp = {
    settings = {
      ruff = {
        lint = {
          run = "onSave",          -- Run on save
        },
      },
    },
    init_options = {
      settings = {
        args = {},
      },
    },
  },
  
  -- JSON with schema support
  jsonls = {
    settings = {
      json = {
        schemas = require("schemastore").json.schemas(),  -- Use schemastore for extensive schema support
        validate = { enable = true },
        format = { enable = true },
      },
    },
  },
  
  -- YAML with schema support
  yamlls = {
    settings = {
      yaml = {
        schemaStore = {
          enable = true,
          url = "https://www.schemastore.org/api/json/catalog.json",
        },
        schemas = require("schemastore").yaml.schemas(),
        format = { enable = true },
        validate = true,
        completion = true,
      },
    },
  },
  
  -- TypeScript/JavaScript
  tsserver = {
    settings = {
      typescript = {
        inlayHints = {  -- Inlay hints configuration
          includeInlayParameterNameHints = "all",
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayEnumMemberValueHints = true,
        },
        suggest = {
          completeFunctionCalls = true,
        },
      },
      javascript = {
        inlayHints = {
          includeInlayParameterNameHints = "all",
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayEnumMemberValueHints = true,
        },
        suggest = {
          completeFunctionCalls = true,
        },
      },
    },
  },
  
  -- CSS
  cssls = {
    settings = {
      css = {
        validate = true,
        lint = {
          unknownAtRules = "ignore",  -- Ignore unknown at-rules for framework compatibility
        },
      },
      scss = {
        validate = true,
        lint = {
          unknownAtRules = "ignore",
        },
      },
      less = {
        validate = true,
        lint = {
          unknownAtRules = "ignore",
        },
      },
    },
  },
  
  -- HTML
  html = {
    settings = {
      html = {
        format = {
          indentInnerHtml = true,
          wrapLineLength = 120,
          wrapAttributes = "auto",
        },
        hover = {
          documentation = true,
          references = true,
        },
        suggest = {
          html5 = true,
        },
      },
    },
    filetypes = { "html", "htmldjango" },  -- Support Django templates
  },
  
  -- Tailwind CSS
  tailwindcss = {
    settings = {
      tailwindCSS = {
        experimental = {
          classRegex = {
            "class[:]\\s*\"([^\"]*)\"",
            "className[:]\\s*\"([^\"]*)\"",
            "class[:]\\s*'([^']*)'",
            "className[:]\\s*'([^']*)'",
            "tw`([^`]*)",
            "tw\\.[^`]+`([^`]*)`",
            "tw\\(.*?\\).*?`([^`]*)",
          },
        },
        includeLanguages = {
          typescript = "javascript",
          typescriptreact = "javascript",
          ["html-eex"] = "html",
          ["phoenix-heex"] = "html",
          heex = "html",
          eelixir = "html",
          elixir = "html",
          elm = "html",
          erb = "html",
          svelte = "html",
          "javascriptreact" = "javascript",
          "astro" = "html",
        },
        validate = true,
      },
    },
  },
  
  -- Vue
  volar = {
    filetypes = { "vue", "typescript", "javascript" },
  },
  
  -- Emmet
  emmet_ls = {
    filetypes = { 
      "html", "css", "scss", "javascript", "javascriptreact", 
      "typescript", "typescriptreact", "vue", "svelte", "astro"
    },
  },
  
  -- Rust
  rust_analyzer = {
    settings = {
      ["rust-analyzer"] = {
        checkOnSave = {
          command = "clippy",  -- Use clippy for more advanced linting
        },
        cargo = {
          allFeatures = true,  -- Enable all cargo features
          loadOutDirsFromCheck = true,
        },
        inlayHints = {
          lifetimeElisionHints = {
            enable = true,
            useParameterNames = true,
          },
          reborrowHints = {
            enable = true,
          },
          closureReturnTypeHints = {
            enable = "always",
          },
        },
        procMacro = {
          enable = true,
        },
      },
    },
  },
  
  -- Go
  gopls = {
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
          shadow = true,
          nilness = true,
          unusedwrite = true,
          useany = true,
        },
        staticcheck = true,
        gofumpt = true,  -- Stricter formatting than gofmt
        hints = {
          assignVariableTypes = true,
          compositeLiteralFields = true,
          compositeLiteralTypes = true,
          constantValues = true,
          functionTypeParameters = true,
          parameterNames = true,
          rangeVariableTypes = true,
        },
      },
    },
  },
  
  -- C/C++
  clangd = {
    cmd = {
      "clangd",
      "--background-index",
      "--suggest-missing-includes",
      "--clang-tidy",
      "--header-insertion=iwyu",
      "--completion-style=detailed",
      "--function-arg-placeholders",
      "--fallback-style=llvm",
    },
  },
  
  -- Java
  jdtls = {
    -- JDTLS has a more complex setup managed by nvim-jdtls
    -- See lua/plugins/langs/java.lua for complete setup
  },
  
  -- Docker
  dockerls = {},
  
  -- Bash
  bashls = {
    filetypes = { "sh", "bash", "zsh" },
  },
  
  -- Terraform
  terraformls = {
    filetypes = { "terraform", "tf", "terraform-vars" },
  },
  
  -- TOML
  taplo = {},
  
  -- Markdown
  marksman = {},
  
  -- LTeX for LaTeX/Markdown spelling and grammar
  ltex = {
    settings = {
      ltex = {
        language = "en-US",
        diagnosticSeverity = "information",
        additionalRules = {
          enablePickyRules = true,
        },
        disabledRules = {},
        hiddenFalsePositives = {},
      },
    },
  },
  
  -- Denols (Deno)
  denols = {
    root_dir = require("lspconfig").util.root_pattern("deno.json", "deno.jsonc"),
  },
  
  -- Ruby
  ruby_ls = {},
  
  -- PHP
  phpactor = {},
  
  -- GraphQL
  graphql = {
    filetypes = { "graphql", "gql", "svelte", "typescriptreact", "javascriptreact" },
  },
  
  -- Astro
  astro = {},
  
  -- Svelte
  svelte = {},
  
  -- Angular
  angularls = {},
  
  -- Elixir
  elixirls = {
    settings = {
      elixirLS = {
        dialyzerEnabled = true,
        fetchDeps = true,
      },
    },
  },
  
  -- Prisma ORM
  prismals = {},
  
  -- SQL
  sqlls = {
    settings = {
      sqlLanguageServer = {
        lint = {
          lintOnChangeDebounce = 500,
        },
      },
    },
  },
  
  -- Typos for spelling errors
  typos_lsp = {},
}

return M
