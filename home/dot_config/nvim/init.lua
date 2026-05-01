-- ~/.config/nvim/init.lua
-- Minimal Neovim starter. Pulls in lazy.nvim and a small handful of
-- well-trodden plugins. Designed as a "light dip into vim" config, not a
-- full IDE replacement -- VS Code remains the heavier editor.

-- ── Bootstrap lazy.nvim ────────────────────────────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── Leader key ─────────────────────────────────────────────────────────────
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ── Sane defaults ──────────────────────────────────────────────────────────
local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.wrap = false
opt.ignorecase = true
opt.smartcase = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.undofile = true
opt.clipboard = "unnamedplus"  -- yank to system clipboard

-- ── Quick keymaps ──────────────────────────────────────────────────────────
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>")
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- ── Plugins ────────────────────────────────────────────────────────────────
require("lazy").setup({
  -- Theme that pairs with the daltonized terminal palette.
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
      require("onedark").setup({ style = "darker" })
      require("onedark").load()
    end,
  },

  -- Statusline.
  { "nvim-lualine/lualine.nvim", opts = { options = { theme = "onedark" } } },

  -- Fuzzy finder.
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",  desc = "Help" },
    },
  },

  -- Treesitter for syntax highlighting + structural editing.
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua", "bash", "json", "yaml", "toml",
          "javascript", "typescript", "tsx",
          "markdown", "markdown_inline",
        },
        highlight = { enable = true },
        indent = { enable = true },
      })
    end,
  },

  -- Comment toggling. `gcc` toggles current line.
  { "numToStr/Comment.nvim", opts = {} },

  -- Git signs in the gutter.
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- LSP scaffolding (Mason auto-installs language servers on demand).
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim", config = true },
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "ts_ls", "bashls" },
      })
      local caps = vim.lsp.protocol.make_client_capabilities()
      local lspconfig = require("lspconfig")
      for _, server in ipairs({ "lua_ls", "ts_ls", "bashls" }) do
        lspconfig[server].setup({ capabilities = caps })
      end
    end,
  },
}, {
  install = { colorscheme = { "onedark" } },
  checker = { enabled = false },
})
