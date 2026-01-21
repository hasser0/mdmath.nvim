local M = {}

local diacritics = require("mdmath.constants").diacritics
local kitty = require("mdmath.kitty")
NS_ID = vim.api.nvim_create_namespace("MdmathEquation")

local function unicode_at(opts)
  return "\u{10EEEE}" .. diacritics[opts.row] .. diacritics[opts.col]
end

local function overlay_lines(mark, equation, buffer)
  local lines = {}
  local dimensions = mark:get_dimensions()
  local start = mark:get_start()
  for i = 1, dimensions.ncells_h do
    local overlay_text = {}
    for j = 1, dimensions.ncells_w do
      overlay_text[#overlay_text + 1] = unicode_at({ row = i, col = j })
    end
    lines[#lines + 1] = table.concat(overlay_text)
  end
  vim.schedule(function()
    for i, line in ipairs(lines) do
      local extmark_id = vim.api.nvim_buf_set_extmark(buffer:get_bufnr(), NS_ID, start.row - 1 + i, start.col, {
        virt_text = { { line, mark:get_color_name() } },
        virt_text_pos = "overlay",
        virt_text_hide = true,
      })
      mark:add_extmark(extmark_id)
    end
  end)
end

local function eol_line(mark, equation, buffer)
  local start = mark:get_start()
  vim.schedule(function()
    local extmark_id = vim.api.nvim_buf_set_extmark(buffer:get_bufnr(), NS_ID, start.row, start.col, {
      virt_text = { { equation:get_message(), "Error" } },
      virt_text_pos = "eol",
    })
    mark:add_extmark(extmark_id)
  end)
end

local function inline_line(mark, equation, buffer)
  local start = mark:get_start()
  local last = mark:get_end()
  local dimensions = equation:get_dimensions()
  local line = {}
  for i = 1, dimensions.ncells_w do
    line[#line + 1] = unicode_at({ row = 1, col = i })
  end
  local extmark_id = vim.api.nvim_buf_set_extmark(buffer:get_bufnr(), NS_ID, start.row, start.col, {
    virt_text = { { table.concat(line), mark:get_color_name() } },
    virt_text_pos = "inline",
    virt_text_hide = true,
    end_col = last.col,
    conceal = ""
  })
  mark:add_extmark(extmark_id)
end

function M.show_overlay(mark, equation, buffer)
  overlay_lines(mark, equation, buffer)
  local start = mark:get_start()
  kitty.display_image_placement({
    tty = buffer:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
    row = start.row,
    col = start.col,
  })
end

function M.show_inline(mark, equation, buffer)
  inline_line(mark, equation, buffer)
  local start = mark:get_start()
  kitty.display_image_placement({
    tty = buffer:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
    row = start.row,
    col = start.col,
  })
end

function M.hide_equation(mark, equation, buffer)
  kitty.delete_image_placement({
    tty = buffer:get_tty(),
    image_id = equation:get_id(),
    placement_id = mark:get_id(),
  })
  mark:delete_extmarks()
end

function M.show_error(mark, equation, buffer)
  eol_line(mark, equation, buffer)
end

function M.hide_error(mark, equation, buffer)
  mark:delete_extmarks()
end

return M
