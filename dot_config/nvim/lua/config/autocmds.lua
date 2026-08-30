-- every colorscheme keeps the terminal background, like gruvbox's transparent_mode
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("transparent_bg", { clear = true }),
  callback = function()
    for _, g in ipairs({ "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn" }) do
      vim.api.nvim_set_hl(0, g, { bg = "NONE" })
    end
  end,
})
