return {version=12,pkgs={{source="lazy",file="lazy.lua",dir="/home/rifle/.local/share/nvim/lazy/noice.nvim",name="noice.nvim",spec=function()
return {
  -- nui.nvim can be lazy loaded
  { "MunifTanjim/nui.nvim", lazy = true },
  {
    "folke/noice.nvim",
  },
}

end,},{source="lazy",file="community",dir="/home/rifle/.local/share/nvim/lazy/plenary.nvim",name="plenary.nvim",spec={"nvim-lua/plenary.nvim",lazy=true,},},},}