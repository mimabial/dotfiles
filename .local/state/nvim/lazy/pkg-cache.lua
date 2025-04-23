return {pkgs={{dir="/home/rifle/.local/share/nvim/lazy/blink.compat",source="lazy",file="lazy.lua",name="blink.compat",spec=function()
return {
  {
    'saghen/blink.compat',
    lazy = true,
  },
}

end,},{dir="/home/rifle/.local/share/nvim/lazy/noice.nvim",source="lazy",file="lazy.lua",name="noice.nvim",spec=function()
return {
  -- nui.nvim can be lazy loaded
  { "MunifTanjim/nui.nvim", lazy = true },
  {
    "folke/noice.nvim",
  },
}

end,},{dir="/home/rifle/.local/share/nvim/lazy/plenary.nvim",source="lazy",file="community",name="plenary.nvim",spec={"nvim-lua/plenary.nvim",lazy=true,},},},version=12,}