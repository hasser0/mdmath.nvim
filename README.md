## ✨ mdmath.nvim

Thanks to Thiago34532 for this project
A Markdown equation previewer inside Neovim, using Kitty Graphics Protocol.

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
  -- Plugin filetypes
  filetypes = { "markdown" },
  -- Color of the equation, can be a highlight group or a hex color.
  foreground = "Normal",
  -- Hide the images when the equation is under the cursor.
  anticonceal = true,
  -- Hide the images when in the Insert Mode.
  hide_on_insert = true,
  -- Center images for display equations
  center_display = true,
  -- Center images for inline equations
  center_inline = true,
  -- Interval between updates (milliseconds).
  update_interval = 400,
  -- Terminal dots per inch checkout with xdpyinfo | grep -B1 dot
  dpi = 96,
}
```

