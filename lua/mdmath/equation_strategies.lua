local M = {}
local fixed_size = {}
local flex_size = {}
local multiline = {}
local error = {}

M.__index = M
fixed_size.__index = fixed_size
flex_size.__index = flex_size
multiline.__index = multiline
error.__index = error

M.fixed_size = fixed_size
M.flex_size = flex_size
M.multiline = multiline
M.error = error

local diacritics = require("mdmath.constants").diacritics
local kitty = require("mdmath.kitty")
NS_ID = vim.api.nvim_create_namespace("MdmathEquation")

local function unicode_at(opts)
  return "\u{10EEEE}" .. diacritics[opts.row] .. diacritics[opts.col]
end

local function unicode_range(row, width)
  local unicode_text = {}
  for j = 1, width do
    unicode_text[#unicode_text + 1] = unicode_at({ row = row, col = j })
  end
  return table.concat(unicode_text)
end

local function hide_equation(mark, equation, window)
  kitty.delete_image_placement({
    tty = window:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
  })
  mark:delete_extmarks()
end

local function hide_error(mark, equation, window)
  mark:delete_extmarks()
end

function fixed_size.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  local mark_dim = mark:get_dimensions()
  vim.schedule(function()
    local text = unicode_range(1, mark_dim.cell_w)
    local extmark_row = start.row
    local extmark_col = start.col
    local extmark_opts = {
      virt_text = {{ text, mark:get_color_name() }},
      virt_text_pos = "overlay",
      virt_text_hide = true,
    }
    local extmark_id = vim.api.nvim_buf_set_extmark(
      window:get_bufnr(), NS_ID,
      extmark_row, extmark_col, extmark_opts
    )
    mark:add_extmark(extmark_id)
  end)
end

function fixed_size.show(mark, equation, window)
  fixed_size.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  kitty.display_image_placement({
    tty = window:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
    row = start.row,
    col = start.col,
  })
end

function fixed_size.hide(mark, equation, window)
  hide_equation(mark, equation, window)
end

function flex_size.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  local image_dim = equation:get_image_dimensions()
  local lines_w = equation:get_lines_width()
  vim.schedule(function()
    local text = unicode_range(1, image_dim.cell_w)
    local extmark_row = start.row
    local extmark_col = start.col
    local extmark_opts = {
      virt_text = {{ text, mark:get_color_name() }},
      virt_text_pos = "inline",
      end_col = start.col + lines_w[1],
      conceal = "",
    }
    local extmark_id = vim.api.nvim_buf_set_extmark(
      window:get_bufnr(), NS_ID,
      extmark_row, extmark_col, extmark_opts
    )
    mark:add_extmark(extmark_id)
  end)
end

function flex_size.show(mark, equation, window)
  flex_size.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  kitty.display_image_placement({
    tty = window:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
    row = start.row,
    col = start.col,
  })
end

function flex_size.hide(mark, equation, window)
  hide_equation(mark, equation, window)
end

function multiline.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  local last = mark:get_end()
  local mark_dim = mark:get_dimensions()
  local image_dim = equation:get_image_dimensions()
  local nvirt_lines = 0
  local normal_lines = 1
  if image_dim.cell_h > mark_dim.cell_h then
    nvirt_lines = image_dim.cell_h - mark_dim.cell_h
  end
  vim.schedule(function()
    for i = 1, image_dim.cell_h do
      local text = unicode_range(i, image_dim.cell_w)
      local extmark_row = 0
      local extmark_col = 0
      local extmark_opts = {}
      if nvirt_lines > 0 then
        extmark_opts = {
          virt_lines = {{{ string.rep(" ", start.col) .. text, mark:get_color_name() }}},
          virt_lines_above = true,
          virt_text_win_col = last.col,
        }
        nvirt_lines = nvirt_lines - 1
        extmark_row = start.row
        extmark_col = start.col - 1
      else
        extmark_opts = {
          virt_text = {{ text, mark:get_color_name() }},
          virt_text_pos = "overlay",
          virt_text_hide = true,
        }
        extmark_row = start.row - 1 + normal_lines
        extmark_col = start.col
        normal_lines = normal_lines + 1
      end
      local extmark_id = vim.api.nvim_buf_set_extmark(
        window:get_bufnr(), NS_ID,
        extmark_row, extmark_col, extmark_opts
      )
      mark:add_extmark(extmark_id)
    end
  end)
end

function multiline.show(mark, equation, window)
  multiline.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  kitty.display_image_placement({
    tty = window:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
    row = start.row,
    col = start.col,
  })
end

function multiline.hide(mark, equation, window)
  hide_equation(mark, equation, window)
end

function error.create_extmarks(mark, equation, window)
  local start = mark:get_start()
  vim.schedule(function()
    local extmark_id = vim.api.nvim_buf_set_extmark(window:get_bufnr(), NS_ID, start.row, start.col, {
      virt_text = {{ equation:get_message(), "Error" }},
      virt_text_pos = "eol",
    })
    mark:add_extmark(extmark_id)
  end)
end

function error.show(mark, equation, window)
  error.create_extmarks(mark, equation, window)
end

function error.hide(mark, equation, window)
  hide_error(mark, equation, window)
end

return M
