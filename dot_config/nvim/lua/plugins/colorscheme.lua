local function dynamic()
  local f = io.open(vim.fn.stdpath("cache") .. "/colorscheme")
  if not f then
    return "gruvbox"
  end
  local name = f:read("*l")
  f:close()
  return (name and name ~= "") and name or "gruvbox"
end

return {
  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    opts = {
      contrast = "hard",
      transparent_mode = true,
      bold = true,
      italic = {
        strings = false,
        emphasis = true,
        comments = true,
        operators = false,
        folds = true,
      },
      strikethrough = true,
      invert_selection = false,
      dim_inactive = false,
    },
  },

  { "folke/tokyonight.nvim", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },
  { "shaunsingh/nord.nvim", lazy = true },
  { "Mofiqul/dracula.nvim", lazy = true },
  -- hard, to sit on the same background as the ghostty everforest
  { "sainnhe/everforest", lazy = true, init = function() vim.g.everforest_background = "hard" end },
  { "sainnhe/gruvbox-material", lazy = true },
  { "oxfist/night-owl.nvim", lazy = true },
  { "loctvl842/monokai-pro.nvim", lazy = true },
  { "Shatur/neovim-ayu", lazy = true },
  { "lunarvim/horizon.nvim", lazy = true },
  { "kepano/flexoki-neovim", lazy = true },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = dynamic(),
    },
  },
}
