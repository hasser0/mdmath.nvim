## ✨ mdmath.nvim

Thanks to Thiago34532 for this project.

This is the same markdown equation previewer inside Neovim, using Kitty Graphics
Protocol with some improvements for inline equations.

## Requirements
  - Neovim version `>=0.10.0`
  - Tree-sitter parser `markdown_inline`
  - NodeJS
  - `npm`
  - ImageMagick v6/v7
  - `rsvg-convert` (from librsvg)
  - Linux/MacOS (not tested in MacOS, please open an issue if you are able to test it)
  - Kitty terminal emulator

## lazy.nvim

```lua
{
    "Thiago4532/mdmath.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    opts = {...},
    build = ":Mdmath build"
}
```

## Configuration

```lua
opts = {
}
```

