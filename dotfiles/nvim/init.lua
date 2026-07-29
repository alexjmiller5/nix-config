-- options
vim.o.number = true
vim.o.clipboard = 'unnamedplus' -- yank/paste ↔ system clipboard
vim.o.ignorecase = true
vim.o.smartcase = true -- case-insensitive search unless query has capitals
vim.o.undofile = true -- undo history survives closing the file

-- macOS-style opt+arrow word jumps (cmd+arrows arrive as Home/End/C-Home/C-End
-- via Ghostty keybinds, which nvim already handles natively)
vim.keymap.set({ 'n', 'v', 'i' }, '<M-Left>', '<C-Left>')
vim.keymap.set({ 'n', 'v', 'i' }, '<M-Right>', '<C-Right>')
vim.keymap.set({ 'n', 'v' }, '<M-Up>', '{')   -- opt+up/down: paragraph jumps, like mac
vim.keymap.set({ 'n', 'v' }, '<M-Down>', '}')
vim.keymap.set('i', '<M-Up>', '<C-o>{')
vim.keymap.set('i', '<M-Down>', '<C-o>}')
vim.keymap.set('i', '<M-BS>', '<C-w>')        -- opt+delete: delete word back
vim.keymap.set('i', '<M-Del>', '<C-o>dw')     -- opt+fn+delete: delete word forward

-- treesitter syntax highlighting
vim.pack.add({ 'https://github.com/nvim-treesitter/nvim-treesitter' })
vim.api.nvim_create_autocmd('FileType', {
  -- ponytail: treesitter where a parser is installed, stock regex highlighting otherwise
  callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
})
