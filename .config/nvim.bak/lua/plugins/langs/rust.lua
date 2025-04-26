--------------------------------------------------------------------------------
-- Rust Development Configuration
--------------------------------------------------------------------------------
--
-- This module provides comprehensive support for Rust development:
--
-- Features:
-- 1. rust-analyzer LSP integration with advanced features
-- 2. Automatic formatting with rustfmt
-- 3. Linting with Clippy
-- 4. Cargo integration for build/run/test
-- 5. Debugging with CodeLLDB
-- 6. Syntax highlighting with TreeSitter
-- 7. Crates.io integration for dependency management
-- 8. Inlay hints for types and parameter names
-- 9. Code navigation and symbol search
-- 10. Advanced completions with snippets
--
-- When opening a Rust file, you get:
-- - Intelligent code completion with documentation
-- - Real-time error checking and linting
-- - Auto-imports and code actions
-- - Type information displayed inline
-- - Cargo.toml dependency management
--------------------------------------------------------------------------------

return {
  -- Rust LSP Configuration
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Configure rust_analyzer LSP
        rust_analyzer = {
          settings = {
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true, -- Enable all Cargo features
                loadOutDirsFromCheck = true,
                runBuildScripts = true,
              },
              -- Enable clippy lints
              checkOnSave = {
                command = "clippy",
                extraArgs = { "--no-deps" },
              },
              -- Inlay hints configuration
              inlayHints = {
                bindingModeHints = {
                  enable = true,
                },
                chainingHints = {
                  enable = true,
                },
                closingBraceHints = {
                  enable = true,
                  minLines = 10,
                },
                closureCaptureHints = {
                  enable = true,
                },
                closureReturnTypeHints = {
                  enable = "always",
                },
                lifetimeElisionHints = {
                  enable = "always",
                  useParameterNames = true,
                },
                parameterHints = {
                  enable = true,
                },
                reborrowHints = {
                  enable = "always",
                },
                typeHints = {
                  enable = true,
                  hideClosureInitialization = false,
                  hideNamedConstructor = false,
                },
              },
              imports = {
                granularity = {
                  group = "module",
                },
                prefix = "self",
              },
              procMacro = {
                enable = true,
                attributes = {
                  enable = true,
                },
              },
              diagnostics = {
                experimental = {
                  enable = true,
                },
              },
              hover = {
                documentation = true,
                links = true,
                memoryLayout = true,
              },
              lens = {
                enable = true,
                references = true,
                methodReferences = true,
                implementations = true,
              },
              completion = {
                fullFunctionSignatures = {
                  enable = true,
                },
              },
            },
          },
          on_attach = function(client, bufnr)
            -- Enable inlay hints if supported
            if vim.lsp.inlay_hint and client.server_capabilities.inlayHintProvider then
              vim.lsp.inlay_hint.enable(bufnr, true)
            end

            -- Custom keymaps for Rust
            local function map(mode, lhs, rhs, desc)
              vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
            end

            -- Add Rust-specific keymaps
            map("n", "<leader>rr", "<cmd>RustRunnables<CR>", "Run Runnables")
            map("n", "<leader>rd", "<cmd>RustDebuggables<CR>", "Debug Runnables")
            map("n", "<leader>rt", "<cmd>RustTest<CR>", "Run Tests")
            map("n", "<leader>rm", "<cmd>RustExpandMacro<CR>", "Expand Macro")
            map("n", "<leader>rc", "<cmd>RustOpenCargo<CR>", "Open Cargo.toml")
            map("n", "<leader>rp", "<cmd>RustParentModule<CR>", "Parent Module")
            map("n", "<leader>rs", "<cmd>RustSSR<CR>", "Structural Search Replace")
          end,
        },
      },
    },
  },

  -- Enhanced Rust development tools
  {
    "simrat39/rust-tools.nvim",
    ft = "rust",
    opts = {
      tools = {
        -- Automatically set inlay hints
        inlay_hints = {
          auto = true,
          show_parameter_hints = true,
          parameter_hints_prefix = "<- ",
          other_hints_prefix = "=> ",
          max_len_align = false,
          max_len_align_padding = 1,
          right_align = false,
          right_align_padding = 7,
          highlight = "Comment",
        },
        hover_actions = {
          border = "rounded",
          auto_focus = true,
        },
      },
      -- Use default LSP server settings from lspconfig
      server = {
        -- Gets settings from the nvim-lspconfig setup
        standalone = false,
      },
      dap = {
        adapter = {
          type = "executable",
          command = "lldb-vscode",
          name = "rt_lldb",
        },
      },
    },
    config = function(_, opts)
      require("rust-tools").setup(opts)
    end,
  },

  -- Crates.io integration for Cargo.toml files
  {
    "saecki/crates.nvim",
    event = { "BufRead Cargo.toml" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("crates").setup({
        null_ls = {
          enabled = true,
          name = "crates.nvim",
        },
        popup = {
          border = "rounded",
          show_version_date = true,
          show_dependency_version = true,
        },
        src = {
          cmp = {
            enabled = true,
          },
        },
      })

      -- Set keymaps for Cargo.toml files
      vim.api.nvim_create_autocmd("BufRead", {
        pattern = "Cargo.toml",
        callback = function(event)
          local bufnr = event.buf

          -- Local keymaps for crates.nvim
          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
          end

          map("n", "<leader>ct", function()
            require("crates").toggle()
          end, "Toggle Crates")
          map("n", "<leader>cr", function()
            require("crates").reload()
          end, "Reload Crates")
          map("n", "<leader>cv", function()
            require("crates").show_versions_popup()
          end, "Show Versions")
          map("n", "<leader>cf", function()
            require("crates").show_features_popup()
          end, "Show Features")
          map("n", "<leader>cd", function()
            require("crates").show_dependencies_popup()
          end, "Show Dependencies")
          map("n", "<leader>cu", function()
            require("crates").update_crate()
          end, "Update Crate")
          map("v", "<leader>cu", function()
            require("crates").update_crates()
          end, "Update Crates")
          map("n", "<leader>ca", function()
            require("crates").update_all_crates()
          end, "Update All Crates")
          map("n", "<leader>cU", function()
            require("crates").upgrade_crate()
          end, "Upgrade Crate")
          map("v", "<leader>cU", function()
            require("crates").upgrade_crates()
          end, "Upgrade Crates")
          map("n", "<leader>cA", function()
            require("crates").upgrade_all_crates()
          end, "Upgrade All Crates")

          -- Auto-update crates version display
          require("crates").show()
        end,
      })
    end,
  },

  -- Better Rust testing
  {
    "nvim-neotest/neotest",
    dependencies = {
      "rouge8/neotest-rust",
    },
    opts = function(_, opts)
      vim.list_extend(opts.adapters or {}, {
        require("neotest-rust")({
          args = { "--no-capture" },
          dap_adapter = "lldb",
        }),
      })
    end,
  },

  -- Configure formatter for Rust
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        rust = { "rustfmt" },
        toml = { "taplo" },
      },
      formatters = {
        rustfmt = {
          args = { "--edition=2021" },
        },
      },
    },
  },

  -- Configure lint for Rust
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        rust = { "cargo" },
      },
      linters = {
        cargo = {
          args = { "clippy", "--message-format=json" },
        },
      },
    },
  },

  -- Configure debugging
  {
    "mfussenegger/nvim-dap",
    opts = function()
      local dap = require("dap")
      if not dap.adapters["codelldb"] then
        dap.adapters["codelldb"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "codelldb",
            args = { "--port", "${port}" },
          },
        }
      end

      -- Add codelldb configuration for Rust
      dap.configurations.rust = {
        {
          name = "Debug Rust Program",
          type = "codelldb",
          request = "launch",
          program = function()
            -- Try common executable names
            local cargo_metadata = vim.fn.system("cargo metadata --format-version 1")
            local metadata = vim.fn.json_decode(cargo_metadata)
            local target_dir = metadata.target_directory
            local package_name = metadata.packages[1].name:gsub("-", "_")

            local candidates = {
              target_dir .. "/debug/" .. package_name,
              target_dir .. "/debug/deps/" .. package_name,
              -- Try to find by asking user
              function()
                return vim.fn.input("Path to executable: ", target_dir .. "/debug/", "file")
              end,
            }

            for _, candidate in ipairs(candidates) do
              if type(candidate) == "function" then
                return candidate()
              elseif vim.fn.executable(candidate) == 1 then
                return candidate
              end
            end

            -- Fallback to manual input
            return vim.fn.input("Path to executable: ", target_dir .. "/debug/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          args = {},
          runInTerminal = false,
        },
        {
          name = "Debug Rust Test",
          type = "codelldb",
          request = "launch",
          program = function()
            local cargo_metadata = vim.fn.system("cargo metadata --format-version 1")
            local metadata = vim.fn.json_decode(cargo_metadata)
            local target_dir = metadata.target_directory

            -- Get path from user
            return vim.fn.input("Path to test executable: ", target_dir .. "/debug/deps/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          args = {},
          runInTerminal = false,
        },
      }
    end,
  },

  -- Add TreeSitter support for Rust
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "rust",
        "toml", -- For Cargo.toml files
      },
    },
  },
}
