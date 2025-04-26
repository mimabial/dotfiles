--------------------------------------------------------------------------------
-- Python Development Configuration
--------------------------------------------------------------------------------
--
-- This module provides comprehensive support for Python development:
--
-- Features:
-- 1. Language Server Protocol (LSP) integration via Pyright and Ruff
-- 2. Syntax highlighting with TreeSitter
-- 3. Automatic formatting with Black and isort
-- 4. Code linting with Flake8 and Mypy
-- 5. Testing integration with pytest
-- 6. Debugging with debugpy
-- 7. Virtual environment management
-- 8. REPL integration
-- 9. Python-specific snippets and templates
-- 10. Auto-import and refactoring tools
--
-- Upon opening a Python file, you'll get:
-- - Intelligent code completion with type information
-- - Real-time diagnostics for errors and style issues
-- - Hover documentation for functions and modules
-- - Jump-to-definition and find-references
-- - Code refactoring options
-- - Auto formatting on save
--------------------------------------------------------------------------------

return {
  -- Python Language Server - Main LSP for Python
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "microsoft/python-type-stubs", -- Type stubs for better completion and type checking
    },
    opts = {
      servers = {
        -- Pyright for type checking and intellisense
        pyright = {
          settings = {
            python = {
              analysis = {
                autoSearchPaths = true,
                diagnosticMode = "workspace",
                useLibraryCodeForTypes = true,
                typeCheckingMode = "basic", -- Options: "off", "basic", "strict"
                inlayHints = {
                  variableTypes = true,
                  functionReturnTypes = true,
                  callArgumentNames = true,
                },
                diagnosticSeverityOverrides = {
                  -- Customize diagnostic severity for specific issues
                  reportGeneralTypeIssues = "warning",
                  reportOptionalMemberAccess = "warning",
                },
              },
              -- This helps with project structure detection
              venvPath = vim.fn.expand("$HOME/.virtualenvs"),
              pythonPath = vim.fn.exepath("python3") or vim.fn.exepath("python"),
            },
          },
          before_init = function(_, config)
            -- Try to detect virtual environment in various standard locations
            local util = require("lspconfig.util")
            local path = util.path

            -- Try to find and use the virtualenv
            local python_bin = vim.fn.exepath("python3") or vim.fn.exepath("python")
            local venv_paths = {
              -- Common virtualenv paths
              ".venv/bin/python",
              "venv/bin/python",
              ".env/bin/python",
              "env/bin/python",
              ".virtualenv/bin/python",
              "virtualenv/bin/python",
              -- Poetry and pipenv
              "./.venv/bin/python",
              "./.poetry/venv/bin/python",
            }

            for _, venv in ipairs(venv_paths) do
              local venv_path = path.join(config.root_dir, venv)
              if vim.fn.executable(venv_path) == 1 then
                python_bin = venv_path
                break
              end
            end

            -- Update configuration with the detected Python interpreter
            config.settings.python.pythonPath = python_bin
          end,
        },

        -- Ruff for linting and formatting
        ruff_lsp = {
          settings = {
            ruff = {
              lint = {
                run = "onSave", -- Run on save
              },
              organizeImports = true, -- Organize imports on format
              fixAll = true, -- Fix all auto-fixable issues
            },
          },
          init_options = {
            settings = {
              args = {},
            },
          },
        },
      },
    },
  },

  -- Python dependency management
  {
    "AckslD/swenv.nvim",
    keys = {
      {
        "<leader>cs",
        function()
          require("swenv.api").pick_venv()
        end,
        desc = "Choose Python venv",
      },
    },
    opts = {
      -- Default paths to find virtualenvs
      venvs_path = { "~/.virtualenvs", "~/venvs", "./.venv", "./venv" },
      -- Detect virtual environments in the current directory
      post_set_venv = function()
        vim.cmd("LspRestart")
        vim.notify("Virtual environment activated and LSP restarted", vim.log.levels.INFO)
      end,
    },
  },

  -- Python REPL integration
  {
    "michaelb/sniprun",
    build = "bash ./install.sh",
    keys = {
      {
        "<leader>cr",
        function()
          require("sniprun").run()
        end,
        desc = "Run Code Snippet",
        mode = { "n", "v" },
      },
      {
        "<leader>cR",
        function()
          require("sniprun").reset()
        end,
        desc = "Reset SnipRun",
      },
    },
    opts = {
      -- Use a floating display window
      display = { "VirtualTextOk", "TerminalOk" },
      -- Interpreter settings for Python
      interpreter_options = {
        Python3_original = {
          venv_path = ".venv", -- Default venv path
          venv = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"), -- Current directory name
        },
      },
      -- Enable for common filetypes
      selected_interpreters = { "Python3_original" },
      repl_enable = { "Python3_original" },
    },
  },

  -- Testing integration
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-python", -- pytest, unittest, etc
    },
    opts = function(_, opts)
      vim.list_extend(opts.adapters or {}, {
        require("neotest-python")({
          dap = { justMyCode = false },
          python = function()
            -- Try to find python in virtualenv
            local venv_python = vim.fn.findfile(".venv/bin/python", vim.fn.getcwd() .. ";")
            if venv_python ~= "" then
              return venv_python
            end
            -- Fallback to system python
            return vim.fn.exepath("python3") or vim.fn.exepath("python")
          end,
          args = { "-v", "--color=yes" },
          runner = "pytest",
        }),
      })
    end,
    keys = {
      { "<leader>ts", "<cmd>Neotest run file<cr>", desc = "Run all tests in file" },
      { "<leader>tt", "<cmd>Neotest run<cr>", desc = "Run nearest test" },
      { "<leader>tT", "<cmd>Neotest run last<cr>", desc = "Run last test" },
      { "<leader>td", "<cmd>Neotest run<cr>", desc = "Debug nearest test" },
      { "<leader>to", "<cmd>Neotest output<cr>", desc = "Show test output" },
      { "<leader>tO", "<cmd>Neotest output-panel toggle<cr>", desc = "Toggle test output panel" },
      { "<leader>ts", "<cmd>Neotest summary toggle<cr>", desc = "Toggle test summary" },
    },
  },

  -- Python debugger configuration
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- Python-specific DAP configuration
      {
        "mfussenegger/nvim-dap-python",
        config = function()
          local path = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
          require("dap-python").setup(path)

          -- Add configurations for common Python applications
          require("dap-python").test_runner = "pytest"

          -- Add custom configurations
          table.insert(require("dap").configurations.python, {
            type = "python",
            request = "launch",
            name = "FastAPI",
            module = "uvicorn",
            args = {
              "main:app",
              "--reload",
            },
          })

          table.insert(require("dap").configurations.python, {
            type = "python",
            request = "launch",
            name = "Django",
            module = "django",
            args = {
              "runserver",
            },
          })

          table.insert(require("dap").configurations.python, {
            type = "python",
            request = "launch",
            name = "Flask",
            module = "flask",
            args = {
              "run",
              "--no-debugger",
              "--no-reload",
            },
            env = {
              FLASK_APP = "${workspaceFolder}/app.py",
            },
          })
        end,
      },
    },
  },

  -- Better formatting
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "ruff_format", "black", "isort" },
      },
      -- Enable auto-formatting on save
      format_on_save = {
        lsp_fallback = true,
        timeout_ms = 500,
      },
    },
  },

  -- Python code refactoring
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      {
        "<leader>rr",
        function()
          require("refactoring").select_refactor()
        end,
        desc = "Select Refactoring",
        mode = { "n", "x" },
      },
      {
        "<leader>re",
        function()
          require("refactoring").refactor("Extract Function")
        end,
        desc = "Extract Function",
        mode = "x",
      },
      {
        "<leader>rf",
        function()
          require("refactoring").refactor("Extract Function To File")
        end,
        desc = "Extract Function To File",
        mode = "x",
      },
      {
        "<leader>rv",
        function()
          require("refactoring").refactor("Extract Variable")
        end,
        desc = "Extract Variable",
        mode = "x",
      },
      {
        "<leader>ri",
        function()
          require("refactoring").refactor("Inline Variable")
        end,
        desc = "Inline Variable",
        mode = { "n", "x" },
      },
      {
        "<leader>rI",
        function()
          require("refactoring").refactor("Inline Function")
        end,
        desc = "Inline Function",
        mode = "n",
      },
    },
    config = function()
      require("refactoring").setup({
        -- Prompt for refactoring prompts
        prompt_func_return_type = {
          python = true,
        },
        prompt_func_param_type = {
          python = true,
        },
      })
    end,
  },

  -- Python docstring generation
  {
    "danymat/neogen",
    opts = {
      languages = {
        python = {
          template = {
            annotation_convention = "google_docstrings",
          },
        },
      },
    },
  },

  -- Add extra TreeSitter parsers if needed
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "python", -- Main Python parser
        "ninja", -- Used by some Python build systems
        "requirements", -- requirements.txt files
        "toml", -- TOML for pyproject.toml
      },
    },
  },

  -- Improved snippets for Python
  {
    "L3MON4D3/LuaSnip",
    config = function()
      require("luasnip").filetype_extend("python", {
        -- Python-specific snippets
        "django",
        "fastapi",
        "flask",
        "sqlalchemy",
        "pytest",
      })
    end,
  },

  -- Extras to improve Python development experience
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    opts = {
      textobjects = {
        select = {
          keymaps = {
            ["aC"] = "@class.outer",
            ["iC"] = "@class.inner",
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
            ["aa"] = "@parameter.outer",
            ["ia"] = "@parameter.inner",
            ["ai"] = "@conditional.outer",
            ["ii"] = "@conditional.inner",
            ["al"] = "@loop.outer",
            ["il"] = "@loop.inner",
            ["ad"] = "@block.outer", -- Use for decorators
            ["id"] = "@block.inner",
          },
        },
      },
    },
  },
}
