--------------------------------------------------------------------------------
-- AI Coding Assistance
--------------------------------------------------------------------------------
--
-- This module configures AI assistance for coding:
-- 1. Copilot/Codeium for code completions
-- 2. Code explanation
-- 3. Documentation generation
-- 4. AI-powered refactoring
--
-- Supports various AI tools including:
-- - GitHub Copilot
-- - Codeium
-- - Tabnine
--------------------------------------------------------------------------------

return {
  -- Codeium - Free alternative to Copilot
  {
    "Exafunction/codeium.nvim",
    event = "InsertEnter",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "hrsh7th/nvim-cmp",
    },
    config = function()
      require("codeium").setup({
        enable_chat = true,
        bin_path = vim.fn.stdpath("data") .. "/codeium/bin",
        config_path = vim.fn.stdpath("config") .. "/codeium",
        api = {
          host = "server.codeium.com",
          port = "443",
        },
      })

      -- Register the codeium source with nvim-cmp
      local cmp = require("cmp")
      local compare = require("cmp.config.compare")

      -- Adjusting the nvim-cmp configuration to insert Codeium
      local cmp_config = cmp.get_config()
      table.insert(cmp_config.sources, 1, { name = "codeium" })

      -- Prioritize Codeium over other sources
      cmp_config.sorting = {
        priority_weight = 2,
        comparators = {
          compare.score, -- Prioritize by match score
          compare.recently_used,
          compare.locality,
          compare.kind,
          compare.sort_text,
          compare.length,
          compare.order,
        },
      }

      cmp.setup(cmp_config)

      -- Setup keymaps for Codeium
      vim.keymap.set("i", "<C-g>", function()
        return vim.fn["codeium#Accept"]()
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<C-n>", function()
        return vim.fn["codeium#CycleCompletions"](1)
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<C-p>", function()
        return vim.fn["codeium#CycleCompletions"](-1)
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<C-x>", function()
        return vim.fn["codeium#Clear"]()
      end, { expr = true, silent = true })

      -- Codeium chat commands
      vim.api.nvim_create_user_command("CodeiumChat", function()
        require("codeium.chat").open()
      end, {})
    end,
  },

  -- Alternative GitHub Copilot (uncomment to use instead of Codeium)
  -- {
  --   "zbirenbaum/copilot.lua",
  --   cmd = "Copilot",
  --   event = "InsertEnter",
  --   config = function()
  --     require("copilot").setup({
  --       suggestion = {
  --         enabled = true,
  --         auto_trigger = true,
  --         debounce = 75,
  --         keymap = {
  --           accept = "<C-g>",
  --           accept_word = "<C-w>",
  --           accept_line = "<C-l>",
  --           next = "<C-n>",
  --           prev = "<C-p>",
  --           dismiss = "<C-x>",
  --         },
  --       },
  --       filetypes = {
  --         yaml = true,
  --         markdown = true,
  --         help = false,
  --         gitcommit = false,
  --         gitrebase = false,
  --         hgcommit = false,
  --         svn = false,
  --         cvs = false,
  --         ["."] = false,
  --       },
  --       copilot_node_command = "node", -- Node.js version must be > 16.x
  --       server_opts_overrides = {},
  --     })
  --   end,
  -- },

  -- Refactoring with AI
  {
    "polypus74/trusty_rusty_replacer",
    dependencies = "stevearc/conform.nvim",
    opts = {
      rust_source_dir = vim.fn.stdpath("data") .. "/trusty_rusty_replacer/",
      add_to_conform = true,
    },
    config = function()
      require("trusty_rusty_replacer").setup({
        formatters = {
          -- Python improvements
          py_improve = {
            cmd = { "python", "-m", "blackd" },
            args = { "--line-length", "88" },
            filetypes = { "python" },
          },
          -- JavaScript/TypeScript improvements
          js_improve = {
            cmd = { "tsx", "format" },
            filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
          },
        },
      })
    end,
  },

  -- Code explanation and AI actions
  {
    "david-kunz/gen.nvim",
    config = function()
      require("gen").setup({
        model = "claude-3-opus-20240229", -- Default model
        display_mode = "float", -- Display output in a floating window
        show_prompt = false, -- Don't show prompt by default
        show_model = false, -- Don't show model name
        no_auto_close = false, -- Auto-close window when done
        debug = false, -- Disable debug info
        -- List of prompts for various coding tasks
        prompts = {
          -- Explain code
          Explain = {
            prompt = "Explain the following code step by step:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Generate documentation
          Doc = {
            prompt = "Generate comprehensive documentation for this code. Include parameters, return types, examples, and edge cases where appropriate:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Refactor code
          Refactor = {
            prompt = "Refactor the following code to improve readability, performance, and adherence to best practices. Do not change behavior. Explain what you improved:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Optimize code
          Optimize = {
            prompt = "Optimize the following code for better performance while preserving functionality. Explain your optimizations:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Find bugs
          FindBugs = {
            prompt = "Review the following code for bugs, edge cases, and potential issues. Be specific about each problem you find, explain why it's a problem, and suggest a fix:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Add tests
          Tests = {
            prompt = "Generate comprehensive unit tests for the following code. Include edge cases, expected inputs/outputs, and any mocks needed:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Add type annotations (for dynamically typed languages)
          TypeAnnotations = {
            prompt = "Add appropriate type annotations to the following code. Explain your choices where the type might not be obvious:\n$text",
            model = "claude-3-opus-20240229",
          },
          -- Convert between languages
          Convert = {
            prompt = "Convert the following code from $filetype to $target_language. Preserve the functionality exactly. Use idiomatic patterns in the target language:\n$text",
            model = "claude-3-opus-20240229",
          },
        },
      })

      -- Set up keymaps for AI assistance
      local function visual_map(key, cmd, desc)
        vim.keymap.set({ "v" }, key, cmd, { desc = desc, noremap = true, silent = true })
      end

      -- AI code actions keymaps
      visual_map("<leader>ae", function()
        require("gen").select_and_run_prompt("Explain")
      end, "AI: Explain Code")
      visual_map("<leader>ad", function()
        require("gen").select_and_run_prompt("Doc")
      end, "AI: Generate Documentation")
      visual_map("<leader>ar", function()
        require("gen").select_and_run_prompt("Refactor")
      end, "AI: Refactor Code")
      visual_map("<leader>ao", function()
        require("gen").select_and_run_prompt("Optimize")
      end, "AI: Optimize Code")
      visual_map("<leader>ab", function()
        require("gen").select_and_run_prompt("FindBugs")
      end, "AI: Find Bugs")
      visual_map("<leader>at", function()
        require("gen").select_and_run_prompt("Tests")
      end, "AI: Generate Tests")
      visual_map("<leader>aa", function()
        require("gen").select_and_run_prompt("TypeAnnotations")
      end, "AI: Add Type Annotations")

      -- Command for converting between languages
      vim.api.nvim_create_user_command("Convert", function(opts)
        -- Get the target language from command arguments
        local target_language = opts.args
        if target_language == "" then
          vim.notify("Please specify a target language: :Convert python", vim.log.levels.ERROR)
          return
        end
        -- Store the target language as an environment variable
        vim.env.target_language = target_language
        -- Run the conversion prompt on the visually selected text
        require("gen").select_and_run_prompt("Convert")
      end, { nargs = 1, range = true })

      -- Map to ask AI a question about the selected code
      visual_map("<leader>aq", function()
        local input = vim.fn.input("Ask AI about this code: ")
        if input ~= "" then
          require("gen").select_and_run({
            prompt = "Regarding the following code:\n$text\n\n" .. input,
            model = "claude-3-opus-20240229",
          })
        end
      end, "AI: Ask Question About Code")

      -- Create a custom chat interface for more complex AI interactions
      vim.api.nvim_create_user_command("AIChat", function()
        -- Create a new buffer in a split window
        vim.cmd("botright new")
        vim.cmd("resize 15")
        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()

        -- Set buffer name and options
        vim.api.nvim_buf_set_name(buf, "AI Chat")
        vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
        vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
        vim.api.nvim_buf_set_option(buf, "swapfile", false)

        -- Set the initial content with instructions
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "# AI Coding Assistant Chat",
          "",
          "Type your question or request below and press <Enter> to send.",
          "Press <Esc> twice to exit.",
          "",
          "> ",
        })

        -- Position cursor at the prompt
        vim.api.nvim_win_set_cursor(win, { 6, 2 })

        -- Enter insert mode
        vim.cmd("startinsert!")

        -- Set up a keymap for sending messages
        vim.keymap.set("i", "<CR>", function()
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local msg = lines[#lines]
          if msg:sub(1, 2) == "> " then
            msg = msg:sub(3)
          end

          -- Add a separator for the response
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
            "",
            "---",
            "",
            "Processing...",
            "",
            "> ",
          })

          -- Immediately position cursor at the new prompt
          vim.api.nvim_win_set_cursor(win, { #vim.api.nvim_buf_get_lines(buf, 0, -1, false), 2 })

          -- Send the message to the AI
          require("gen").run({
            prompt = msg,
            model = "claude-3-opus-20240229",
            template = "",
            callback = function(output, job)
              -- Replace "Processing..." with the actual response
              local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
              local processing_line = 0
              for i, line in ipairs(all_lines) do
                if line == "Processing..." then
                  processing_line = i - 1
                  break
                end
              end

              if processing_line > 0 then
                -- Replace the processing line with the actual response
                vim.api.nvim_buf_set_lines(buf, processing_line, processing_line + 1, false, vim.split(output, "\n"))
                -- Ensure cursor is at the prompt
                vim.api.nvim_win_set_cursor(win, { #vim.api.nvim_buf_get_lines(buf, 0, -1, false), 2 })
              end
            end,
          })
        end, { buffer = buf })

        -- Escape to exit
        local escape_count = 0
        vim.keymap.set("i", "<Esc>", function()
          escape_count = escape_count + 1
          if escape_count >= 2 then
            vim.cmd("q!")
          else
            -- Reset count after a delay
            vim.defer_fn(function()
              escape_count = 0
            end, 500)
          end
          return "<Esc>"
        end, { buffer = buf, expr = true })
      end, {})
    end,
  },
}
