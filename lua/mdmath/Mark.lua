Mark = {}
Mark.__index = Mark

local diacritics = require("mdmath.constants").diacritics
local kitty = require("mdmath.kitty")
local config = require("mdmath.config").opts
NS_ID = vim.api.nvim_create_namespace("mdmath-equation")
MARK_ID = 1

local function _get_id()
  MARK_ID = MARK_ID + 1
  return MARK_ID
end

local function unicode_at(opts)
  return "\u{10EEEE}" .. diacritics[opts.row] .. diacritics[opts.col]
end

local function linewidth(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  return line and line[1]:len() or 0
end

function Mark.hash_mark(id)
  return tostring(id)
end

function Mark.compute_offset(bufnr, row, col)
  local row_offset = vim.api.nvim_buf_get_offset(bufnr, row)
  if row_offset == -1 then
    return nil
  end

  local len = linewidth(bufnr, row)
  local col_offset = len < col and len or col
  return row_offset + col_offset
end

---@param opts {
---buffer: any,
---equation: any,
---color_name: string,
---ncells_w: number,
---ncells_h: number,
---start_row: number,
---start_col: number,
---end_row: number,
---end_col: number,
---}
function Mark.new(opts)
  local self = {}
  setmetatable(self, Mark)

  self.buffer = opts.buffer
  self.equation = opts.equation
  self.id = _get_id()
  self.hash = Mark.hash_mark(self.id)

  self.extmark_ids = {}

  -- positions
  self.start_row = opts.start_row
  self.start_col = opts.start_col
  self.ncells_h = opts.ncells_h
  self.ncells_w = opts.ncells_w
  self.offset = Mark.compute_offset(opts.buffer:get_bufnr(), opts.start_row, opts.start_col)
  self.length = Mark.compute_offset(opts.buffer:get_bufnr(), opts.end_row, opts.end_col) - self.offset

  self.is_displayed = false
  self.text_ready = false
  self.is_valid = true
  self.color_name = opts.color_name

  return self
end

function Mark:free()
  self:hide()
  self.buffer:remove_mark(self)
  self.equation:remove_mark(self)
end

function Mark:get_hash()
  return self.hash
end

function Mark:is_alive()
  return self.is_valid
end

function Mark:contains_offset(offset)
  return self.offset <= offset and offset <= (self.offset + self.length)
end

function Mark:is_location(row, col)
  return self.start_row == row and self.start_col == col
end

---@param opts {
---start_row: number,
---start_col: number,
---start_offset: number,
---old_end_row: number,
---old_end_col: number,
---old_offset: number,
---new_end_row: number,
---new_end_col: number,
---new_offset: number,
---}
function Mark:update_position(opts)
  if not self.is_valid then
    return
  end

  local offset = self.offset
  local length = self.length
  local row = self.start_row
  local col = self.start_col

  -- unchanged mark
  if offset + length <= opts.start_offset then
    return
  end

  -- deleted mark
  if offset < opts.old_offset then
    self:free()
    return
  end

  -- update mark
  offset = offset + opts.new_offset - opts.old_offset
  row = row + opts.new_end_row - opts.old_end_row
  if row == opts.new_end_row then
    col = col + opts.new_end_col - opts.old_end_col
  end

  self.start_row = row
  self.start_col = col
  self.offset = offset
end

function Mark:redraw()
  if self.is_displayed then
    self.is_displayed = false
    self:show()
  else
    self.is_displayed = true
    self:hide()
  end
end

function Mark:show()
  if self.is_displayed then
    return
  end
  if self.equation:is_message() then
    self:_show_error()
  else
    self:_show_equation()
  end
end

function Mark:hide()
  if not self.is_displayed then
    return
  end
  if self.equation:is_message() then
    self:_hide_error()
  else
    self:_hide_equation()
  end
end


function Mark:_show_equation()
  self:_process_overlay_lines()
  if not self.equation:is_ready() then
    vim.defer_fn(function()
      self:show()
    end, config.retry_mark_draw)
    return
  end
  kitty.display_image_placement({
    tty = self.buffer:get_tty(),
    image_id = self.equation:get_id(),
    placement_id = self.id,
    row = self.start_row,
    col = self.start_col,
  })
  self.is_displayed = true
end

function Mark:_show_error()
  self:_process_eol_line()
  self.is_displayed = true
end

function Mark:_hide_equation()
  kitty.delete_image_placement({
    tty = self.buffer:get_tty(),
    image_id = self.equation:get_id(),
    placement_id = self.id,
  })
  self.is_displayed = false
  for _, extmark_id in ipairs(self.extmark_ids) do
    vim.api.nvim_buf_del_extmark(self.buffer:get_bufnr(), NS_ID, extmark_id)
  end
  self.is_displayed = false
end

function Mark:_hide_error()
  for _, extmark_id in ipairs(self.extmark_ids) do
    vim.api.nvim_buf_del_extmark(self.buffer:get_bufnr(), NS_ID, extmark_id)
  end
  self.is_displayed = false
end

function Mark:_process_eol_line()
  vim.schedule(function()
    local extmark_id = vim.api.nvim_buf_set_extmark(self.buffer:get_bufnr(), NS_ID, self.start_row, self.start_col, {
      virt_text = { { self.equation:get_message(), "Error" } },
      virt_text_pos = "eol",
    })
    self.extmark_ids[#self.extmark_ids + 1] = extmark_id
    self.text_ready = true
  end)
end

function Mark:_process_overlay_lines()
  local overlay_lines = {}
  for i = 1, self.ncells_h do
    local overlay_text = {}
    for j = 1, self.ncells_w do
      overlay_text[#overlay_text + 1] = unicode_at({ row = i, col = j })
    end
    overlay_lines[#overlay_lines + 1] = table.concat(overlay_text)
  end
  vim.schedule(function()
    for i, line in ipairs(overlay_lines) do
      local extmark_id = vim.api.nvim_buf_set_extmark(self.buffer:get_bufnr(), NS_ID, self.start_row - 1 + i, self.start_col, {
        virt_text = { { line, self.color_name } },
        virt_text_pos = "overlay",
        virt_text_hide = true,
      })
      self.extmark_ids[#self.extmark_ids + 1] = extmark_id
    end
    self.text_ready = true
  end)
end

return Mark
