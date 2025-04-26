return {
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
}
