## ✨ mdmath.nvim

Thanks to Thiago34532 for this project.

This is the same markdown equation previewer inside Neovim, using Kitty Graphics
Protocol with some improvements for inline equations and other display options.

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
  -- Display strategy per mode
  --   hide_all: hides all marks
  --   show_all: show all marks
  --   hide_in_cursor: hides marks under cursor. Not recommended with
  --                   AdjustTextToEquation for inline-equations, use
  --                   hide_in_line instead for that
  --   hide_in_line: hides all marks in current line.
  insert_strategy = "hide_all",
  normal_strategy = "hide_in_line",
  -- Display strategy for individual equations.
  -- For inline-equations, height is limited to cell height.
  --   AdjustTextToEquation: Shrinks or extend text as needed to fit  image size
  --   AdjustEquationToText: Image size is limited by text area
  inline_strategy = "AdjustEquationToText",
  display_strategy = "AdjustTextToEquation",
  -- Center images for equation types
  center_display = true,
  center_inline = true,
  -- Number of pixels to use as padding from above and below
  -- lower level for equations
  --
  --
  -----------------------------------------------------------------------
  ------------------.______--------------------------_-------------------
  --                | ____|_  ____ _ _ __ ___  _ __ | | ___
  --                |  _| \ \/ / _` | '_ ` _ \| '_ \| |/ _ \
  --                | |___ >  < (_| | | | | | | |_) | |  __/
  --                |_____/_/\_\__,_|_| |_| |_| .__/|_|\___|
  --------------------------------------------|_|------------------------
  -----------------------------------------------------------------------
  -- when image cellHeight < (2*pixelPadding) + imageHeight image is centered,
  -- and pixel padding is ignored, otherwise images are generated with this
  -- distance as a baseline for equations. Pixel padding is calculated as
  --
  --                cell_height_in_pixels * bottom_line_ratio
  --
  -- expected to be in [0.0, 0.3] range
  bottom_line_ratio = 0.15,
  -- Milliseconds to retry mark redraw
  retry_mark_draw = 3,
  -- Milliseconds to wait for no events to redraw.
  update_interval = 50,
  -- Zoom to apply to display equations. Not direct scale
  display_zoom = 1.2,
}
```

