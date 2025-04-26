return {
  "f4z3r/gruvbox-material.nvim",
  name = "gruvbox-material",
  lazy = false,
  priority = 1000,
  config = function()
    require("gruvbox-material").setup({
      italics = true,
      contrast = "hard",
      comments = {
        italics = true,
      },
      background = {
        transparent = false,
      },
      float = {
        force_background = false,
      },
      signs = {
        highlight = true,
      },
    })
  end,
}
