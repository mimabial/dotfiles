--------------------------------------------------------------------------------
-- Debugging Configuration
--------------------------------------------------------------------------------
--
-- This module provides debugging support via the Debug Adapter Protocol (DAP)
--
-- Features:
-- 1. Unified debugging interface for multiple languages
-- 2. Breakpoints, conditional breakpoints, and logpoints
-- 3. Variable inspection and watches
-- 4. Call stack navigation
-- 5. Pretty UI for debugging state
-- 6. REPL integration
-- 7. Language-specific adapters
--
-- Supported languages:
-- * Python (via debugpy)
-- * JavaScript/TypeScript (via vscode-js-debug)
-- * C/C++/Rust (via codelldb)
-- * Go (via delve)
-- * Java (via java-debug)
-- * PHP (via vscode-php-debug)
-- * and many others
--
-- Usage:
-- 1. Set breakpoints with <leader>db
-- 2. Start debugging with <leader>dd
-- 3. Step through code with <leader>ds, <leader>di, <leader>dc
-- 4. Inspect variables in the UI or hover over them
--------------------------------------------------------------------------------

return {
  -- The Core Debugging Engine
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- Creates a beautiful debugger UI
      "rcarriga/nvim-dap-ui",
      
      -- Virtual text for the debugger
      "theHamsta/nvim-dap-virtual-text",
      
      -- Mason integration to automatically install debuggers
      "jay-babu/mason-nvim-dap.nvim",
      
      -- Telescope integration for debugger commands
      "nvim-telescope/telescope-dap.nvim",
    },
    keys = {
      -- Debugger control keymaps
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Breakpoint Condition" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to Cursor" },
      { "<leader>dg", function() require("dap").goto_() end, desc = "Go to Line (no execute)" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
      { "<leader>dj", function() require("dap").down() end, desc = "Down" },
      { "<leader>dk", function() require("dap").up() end, desc = "Up" },
      { "<leader>dl", function() require("dap").run_last() end, desc = "Run Last" },
      { "<leader>do", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>dO", function() require("dap").step_over() end, desc = "Step Over" },
      { "<leader>dp", function() require("dap").pause() end, desc = "Pause" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
      { "<leader>ds", function() require("dap").session() end, desc = "Session" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
      { "<leader>dw", function() require("dap.ui.widgets").hover() end, desc = "Widgets" },
      
      -- Keymap to launch a debug session for the current project
      { "<leader>dd", function()
        -- Auto-detect and launch based on filetype or directory structure
        local filetype = vim.bo.filetype
        
        if filetype == "python" then
          -- Launch the active Python file
          require("dap").launch({
            type = "python",
            request = "launch",
            name = "Launch Current File",
            program = "${file}",
            pythonPath = function()
              local venv_path = os.getenv("VIRTUAL_ENV")
              if venv_path then
                return venv_path .. "/bin/python"
              end
              return vim.fn.exepath("python3") or vim.fn.exepath("python") or "python"
            end,
          })
        elseif filetype == "javascript" or filetype == "typescript" or filetype == "javascriptreact" or filetype == "typescriptreact" then
          -- Launch for JS/TS
          require("dap").launch({
            type = "pwa-node",
            request = "launch",
            name = "Launch Current File",
            program = "${file}",
            cwd = "${workspaceFolder}",
          })
        elseif filetype == "go" then
          -- Launch for Go
          require("dap").launch({
            type = "go",
            request = "launch",
            name = "Debug",
            program = "${file}",
          })
        elseif filetype == "java" then
          -- Launch for Java
          require("jdtls").debug_main_class_in_project()
        elseif filetype == "rust" or filetype == "c" or filetype == "cpp" then
          -- Launch for Rust/C/C++
          require("dap").launch({
            type = "codelldb",
            request = "launch",
            name = "Debug",
            program = function()
              -- Check for common executable locations
              local executables = {
                "target/debug/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),  -- Rust
                "build/debug/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),   -- C/C++
                "build/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),         -- Generic build
              }
              
              for _, executable in ipairs(executables) do
                if vim.fn.filereadable(executable) == 1 then
                  return executable
                end
              end
              
              -- Let user select the executable
              return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
            end,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
          })
        else
          -- Fallback to showing available configurations
          require("telescope").extensions.dap.configurations()
        end
      end, desc = "Start Debugging" },
      
      -- UI control keymaps
      { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle Debugger UI" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Evaluate Expression", mode = {"n", "v"} },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      
      -- Configure UI
      dapui.setup({
        icons = { expanded = "▾", collapsed = "▸", current_frame = "→" },
        controls = {
          icons = {
            pause = "⏸",
            play = "▶",
            step_into = "⏎",
            step_over = "⏭",
            step_out = "⏮",
            step_back = "⏪",
            run_last = "⟲",
            terminate = "⏹",
            disconnect = "⏏",
          },
        },
        layouts = {
          {
            elements = {
              -- Top panel elements
              { id = "scopes", size = 0.25 },
              { id = "breakpoints", size = 0.25 },
              { id = "stacks", size = 0.25 },
              { id = "watches", size = 0.25 },
            },
            position = "left",
            size = 40,
          },
          {
            elements = {
              -- Bottom panel elements
              { id = "repl", size = 0.5 },
              { id = "console", size = 0.5 },
            },
            position = "bottom",
            size = 10,
          },
        },
        floating = {
          max_height = nil,
          max_width = nil,
          border = "rounded",
          mappings = {
            close = { "q", "<Esc>" },
          },
        },
      })
      
      -- Configure virtual text
      require("nvim-dap-virtual-text").setup({
        enabled = true,
        enabled_commands = true,
        highlight_changed_variables = true,
        highlight_new_as_changed = false,
        show_stop_reason = true,
        commented = false,
        virt_text_pos = "eol",
        all_frames = false,
        virt_text_win_col = nil,
      })
      
      -- Add Telescope integration
      require("telescope").load_extension("dap")
      
      -- Set up icons for breakpoints, stopped, etc.
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition", linehl = "", numhl = "" })
      vim.fn.sign_define("DapLogPoint", { text = "◆", texthl = "DapLogPoint", linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "●", texthl = "DapBreakpointRejected", linehl = "", numhl = "" })
      
      -- Automatically open UI when debugging starts
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
      
      -- Highlight groups for debugging
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff0000" })
      vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#ff00ff" })
      vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#00ffff" })
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#00ff00", bg = "#333333" })
      vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#ff3333" })
    end,
  },
  
  -- Mason integration for DAP
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = { "williamboman/mason.nvim" },
    cmd = { "DapInstall", "DapUninstall" },
    opts = {
      -- List of debuggers to automatically install
      ensure_installed = {
        "python",            -- Python debugging
        "codelldb",          -- C/C++/Rust debugging
        "js",                -- JavaScript/TypeScript debugging
        "php",               -- PHP debugging
        "delve",             -- Go debugging
        "javadbg",           -- Java debugging
        "kotlin-debug-adapter" -- Kotlin debugging
      },
      automatic_installation = true,
      
      -- Set up DAP adapters after installation
      handlers = {
        -- Default handler for all debuggers
        function(config)
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- Python specific configuration
        python = function(config)
          config.adapters = {
            type = "executable",
            command = "python",
            args = { "-m", "debugpy.adapter" },
          }
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- Rust/C/C++ specific configuration
        codelldb = function(config)
          config.adapters = {
            type = "server",
            port = "${port}",
            executable = {
              command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
              args = { "--port", "${port}" },
            },
          }
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- JavaScript/TypeScript specific configuration
        js = function(config)
          require("mason-nvim-dap").default_setup(config) -- don't forget this!
          
          -- Add node adapter
          local js_adapter = {
            type = "executable",
            command = "node",
            args = { vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}" },
          }
          
          require("dap").adapters["pwa-node"] = js_adapter
          require("dap").adapters["node"] = js_adapter
          require("dap").adapters["chrome"] = js_adapter
          require("dap").adapters["pwa-chrome"] = js_adapter
          
          -- Configure launch parameters for js/ts
          local js_configs = {
            {
              type = "pwa-node",
              request = "launch",
              name = "Launch file",
              program = "${file}",
              cwd = "${workspaceFolder}",
            },
            {
              type = "pwa-node",
              request = "attach",
              name = "Attach",
              processId = require("dap.utils").pick_process,
              cwd = "${workspaceFolder}",
            },
            {
              type = "pwa-chrome",
              request = "launch",
              name = "Launch Chrome",
              url = "http://localhost:3000",
              webRoot = "${workspaceFolder}",
              userDataDir = "${workspaceFolder}/.vscode/chrome-debug-profile",
            },
            -- Add configurations for popular frameworks
            {
              type = "pwa-node",
              request = "launch",
              name = "Debug Jest Tests",
              -- trace = true, -- include debugger info
              runtimeExecutable = "node",
              runtimeArgs = {
                "./node_modules/jest/bin/jest.js",
                "--runInBand",
              },
              rootPath = "${workspaceFolder}",
              cwd = "${workspaceFolder}",
              console = "integratedTerminal",
              internalConsoleOptions = "neverOpen",
            },
            {
              type = "pwa-node",
              request = "launch",
              name = "Debug Mocha Tests",
              -- trace = true, -- include debugger info
              runtimeExecutable = "node",
              runtimeArgs = {
                "./node_modules/mocha/bin/mocha.js",
              },
              rootPath = "${workspaceFolder}",
              cwd = "${workspaceFolder}",
              console = "integratedTerminal",
              internalConsoleOptions = "neverOpen",
            },
            -- Next.js configuration
            {
              type = "pwa-node",
              request = "launch",
              name = "Next.js",
              runtimeExecutable = "npm",
              runtimeArgs = { "run", "dev" },
              env = { NEXTAUTH_URL = "http://localhost:3000" },
              resolveSourceMapLocations = {
                "${workspaceFolder}/**",
                "!**/node_modules/**",
              },
              rootPath = "${workspaceFolder}",
              cwd = "${workspaceFolder}",
              console = "integratedTerminal",
              internalConsoleOptions = "neverOpen",
            },
          }
          
          -- Add these configuration to dap
          for _, config in ipairs(js_configs) do
            table.insert(require("dap").configurations.javascript, config)
            table.insert(require("dap").configurations.typescript, config)
          end
        end,
        
        -- Go debugging
        delve = function(_)
          require("dap").adapters.delve = {
            type = "server",
            port = "${port}",
            executable = {
              command = "dlv",
              args = { "dap", "-l", "127.0.0.1:${port}" },
            },
          }
          
          -- configurations
          require("dap").configurations.go = {
            {
              type = "delve",
              name = "Debug",
              request = "launch",
              program = "${file}",
            },
            {
              type = "delve",
              name = "Debug test file",
              request = "launch",
              mode = "test",
              program = "${file}",
            },
            {
              type = "delve",
              name = "Debug test (go.mod)",
              request = "launch",
              mode = "test",
              program = "./${relativeFileDirname}",
            },
          }
        end,
        
        -- PHP debugging
        php = function(_)
          require("dap").adapters.php = {
            type = "executable",
            command = "node",
            args = { vim.fn.stdpath("data") .. "/mason/packages/php-debug-adapter/extension/out/phpDebug.js" }
          }
          
          require("dap").configurations.php = {
            {
              type = "php",
              request = "launch",
              name = "Listen for Xdebug",
              port = 9003,
              pathMappings = {
                ["/var/www/html"] = "${workspaceFolder}"
              }
            }
          }
        end,
      },
    },
  },
  
  -- Enhanced testing with integrated debugging support
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-plenary",
      "nvim-neotest/neotest-go",
      "haydenmeade/neotest-jest",
      "nvim-neotest/neotest-vim-test",
    },
    opts = {
      -- Common test adapter configuration
      adapters = {
        require("neotest-python")({
          dap = { justMyCode = false },
          runner = "pytest",
          args = { "-xvs" },
        }),
        require("neotest-jest")({
          jestCommand = "npm test --",
          jestConfigFile = "jest.config.js",
          env = { CI = true },
          cwd = function()
            return vim.fn.getcwd()
          end,
        }),
        require("neotest-go"),
        require("neotest-plenary"),
        require("neotest-vim-test")({
          ignore_file_types = { "python", "javascript", "typescript", "go", "rust" },
        }),
      },
      -- UI customization
      icons = {
        running = "󰑮",
        passed = "✅",
        failed = "❌",
        skipped = "⏭️",
        unknown = "❓",
      },
      status = {
        virtual_text = true,
        signs = true,
      },
      output = {
        open_on_run = true,
      },
      quickfix = {
        open = function()
          require("trouble").open({ mode = "quickfix", focus = false })
        end,
      },
      consumers = {
        -- Integrate with other plugins
        overseer = require("neotest.consumers.overseer"),
      },
      discovery = {
        enabled = true,
      },
      -- Integrate with DAP
      dap = true,
      strategies = {
        integrated = {
          width = 180,
          height = 40,
        },
      },
    },
    config = function(_, opts)
      require("neotest").setup(opts)
      
      -- Add keymaps for testing with DAP
      vim.keymap.set("n", "<leader>td", function()
        require("neotest").run.run({ strategy = "dap" })
      end, { desc = "Debug Nearest Test" })
      
      vim.keymap.set("n", "<leader>tD", function()
        require("neotest").run.run_last({ strategy = "dap" })
      end, { desc = "Debug Last Test" })
    end,
    keys = {
      { "<leader>tt", function() require("neotest").run.run() end, desc = "Run Nearest Test" },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run Current File" },
      { "<leader>tT", function() require("neotest").run.run_last() end, desc = "Run Last Test" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Toggle Summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Show Output" },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Output Panel" },
      { "<leader>tw", function() require("neotest").watch.toggle() end, desc = "Toggle Watch Mode" },
      { "<leader>tr", function() require("neotest").run.stop() end, desc = "Stop Test Run" },
    },
  },
}
Rejected", { text = "●", texthl = "DapBreakpointRejected", linehl = "", numhl = "" })
      
      -- Automatically open UI when debugging starts
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
      
      -- Highlight groups for debugging
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff0000" })
      vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = "#ff00ff" })
      vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#00ffff" })
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#00ff00", bg = "#333333" })
      vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#ff3333" })
    end,
  },
  
  -- Mason integration for DAP
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = { "williamboman/mason.nvim" },
    cmd = { "DapInstall", "DapUninstall" },
    opts = {
      -- List of debuggers to automatically install
      ensure_installed = {
        "python",            -- Python debugging
        "codelldb",          -- C/C++/Rust debugging
        "js",                -- JavaScript/TypeScript debugging
        "php",               -- PHP debugging
        "delve",             -- Go debugging
        "javadbg",           -- Java debugging
        "kotlin-debug-adapter" -- Kotlin debugging
      },
      automatic_installation = true,
      
      -- Set up DAP adapters after installation
      handlers = {
        -- Default handler for all debuggers
        function(config)
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- Python specific configuration
        python = function(config)
          config.adapters = {
            type = "executable",
            command = "python",
            args = { "-m", "debugpy.adapter" },
          }
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- Rust/C/C++ specific configuration
        codelldb = function(config)
          config.adapters = {
            type = "server",
            port = "${port}",
            executable = {
              command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
              args = { "--port", "${port}" },
            },
          }
          require("mason-nvim-dap").default_setup(config)
        end,
        
        -- JavaScript/TypeScript specific configuration
        js = function(config)
          require("mason-nvim-dap").default_setup(config) -- don't forget this!
          
          -- Add node adapter
          local js_adapter = {
            type = "executable",
            command = "node",
            args = { vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}" },
          }
          
          require("dap").adapters["pwa-node"] = js_adapter
          require("dap").adapters["node"] = js_adapter
          require("dap").adapters["chrome"] = js_adapter
          require("dap").adapters["pwa-chrome"] = js_adapter
          
          -- Configure launch parameters for js/ts
          local js_configs = {
            {
              type = "pwa-node",
              request = "launch",
              name = "Launch file",
              program = "${file}",
              cwd = "${workspaceFolder}",
            },
            {
              type = "pwa-node",
              request = "attach",
              name = "Attach",
              processId = require("dap.utils").pick_process,
              cwd = "${workspaceFolder}",
            },
            {
              type = "pwa-chrome",
              request = "
