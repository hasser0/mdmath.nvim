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
  -- Plugin filetypes
  filetypes = { "markdown" },
  -- Color of the equation, can be a highlight group or a hex color.
  foreground = "Normal",
  -- Display strategy
  --   hide_all: hides all marks
  --   show_all: show all marks
  --   hide_in_cursor: hides marks under cursor
  --   hide_in_line: hides all marks in line
  -- Display strategy for normal mode
  insert_strategy = "hide_all",
  -- Display strategy for normal mode
  normal_strategy = "hide_in_line",
  -- Display strategy for individual equations
  --   show_overlay
  --   show_inline
  inline_strategy_show = "show_inline",
  -- Center images for display equations
  center_display = true,
  -- Center images for inline equations
  center_inline = true,
  -- Number of pixels to use as padding from above and below
  pixel_padding = 0,
  -- Pixels height ratio to use as baseline to align equations vertically
  bottom_line_ratio = 0.15,
  -- Retry marks in milliseconds
  retry_mark_draw = 3,
}
```

