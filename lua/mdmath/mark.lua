local Mark = {}
Mark.__index = Mark

local utils = require("mdmath.utils")
MARK_ID = 1

local function _get_id()
  MARK_ID = MARK_ID + 1
  return MARK_ID
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
  self.hash = utils.mark.hash_mark(self.id)

  self.extmark_ids = {}

  -- positions
  self.start_row = opts.start_row
  self.start_col = opts.start_col
  self.end_row = opts.end_row
  self.end_col = opts.end_col
  self.ncells_h = opts.ncells_h
  self.ncells_w = opts.ncells_w
  self.offset = utils.mark.compute_offset(opts.buffer:get_bufnr(), opts.start_row, opts.start_col)
  self.length = utils.mark.compute_offset(opts.buffer:get_bufnr(), opts.end_row, opts.end_col) - self.offset

  self.is_displayed = false
  self.is_valid = true
  self.color_name = opts.color_name

  return self
end

function Mark:free()
  self:hide()
  self.buffer:remove_mark(self)
  self.equation:remove_mark(self)
  self.is_valid = false
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

function Mark:contains_row(row)
  return self.start_row <= row and row < self.start_row + self.ncells_h
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
    self.is_valid = false
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

function Mark:show()
  if self.is_displayed then
    return
  end
  self.is_displayed = true
  self.equation:show_mark(self)
end

function Mark:hide()
  if not self.is_displayed then
    return
  end
  self.is_displayed = false
  self.equation:hide_mark(self)
end

function Mark:invalidate()
  self.is_valid = false
end

function Mark:validate()
  self.is_valid = true
end

function Mark:delete_extmarks()
  for _, extmark_id in ipairs(self.extmark_ids) do
    vim.api.nvim_buf_del_extmark(self.buffer:get_bufnr(), NS_ID, extmark_id)
  end
end

function Mark:get_dimensions()
  return {
    cell_h = self.ncells_h,
    cell_w = self.ncells_w,
  }
end

function Mark:get_start()
  return {
    row = self.start_row,
    col = self.start_col,
  }
end

function Mark:get_end()
  return {
    row = self.end_row,
    col = self.end_col,
  }
end

function Mark:add_extmark(extmark_id)
  self.extmark_ids[#self.extmark_ids + 1] = extmark_id
end

function Mark:get_color_name()
  return self.color_name
end

function Mark:get_id()
  return self.id
end

return Mark
