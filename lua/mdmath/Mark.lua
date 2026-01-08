Mark = {}

local diacritics = require("mdmath.constants").diacritics
local kitty = require("mdmath.kitty")
local config = require("mdmath.config").opts
NS_ID = vim.api.nvim_create_namespace("mdmath-equation")

local function unicode_at(opts)
  return "\u{10EEEE}" .. diacritics[opts.row] .. diacritics[opts.col]
end

local function linewidth(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  return line and line[1]:len() or 0
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
---mark_id: number,
---bufnr: number,
---color_name: string,
---ncells_w: number,
---ncells_h: number,
---image_id: number,
---start_row: number,
---start_col: number,
---end_row: number,
---end_col: number,
---callback: any,
---tty: any,
---}
function Mark:new(opts)
  local mark = {}
  setmetatable(mark, { __index = self })

  -- ids
  mark.bufnr = opts.bufnr
  mark.image_id = opts.image_id
  mark.mark_id = opts.mark_id
  mark.extmark_ids = {}

  -- positions
  mark.start_row = opts.start_row
  mark.start_col = opts.start_col
  mark.ncells_h = opts.ncells_h
  mark.ncells_w = opts.ncells_w
  mark.tty = opts.tty
  mark.offset = Mark.compute_offset(opts.bufnr, opts.start_row, opts.start_col)
  mark.length = Mark.compute_offset(opts.bufnr, opts.end_row, opts.end_col) - mark.offset

  mark.is_displayed = false
  mark.overlay_ready = false
  mark.is_valid = true
  mark.equation_callback = opts.callback
  mark.color_name = opts.color_name

  return mark
end

function Mark:free()
  if self.is_displayed then
    kitty.delete_image_placement({
      tty = self.tty,
      image_id = self.image_id,
      placement_id = self.mark_id,
    })
    self.is_displayed = false
  end
  for _, extmark_id in ipairs(self.extmark_ids) do
    vim.api.nvim_buf_del_extmark(self.bufnr, NS_ID, extmark_id)
  end
end

function Mark:display()
  if self.is_displayed then
    return
  end
  self:_process_overlay_lines()
  if not self.equation_callback() then
    vim.defer_fn(function()
      self:display()
    end, config.retry_mark_draw)
    return
  end
  kitty.display_image_placement({
    tty = self.tty,
    image_id = self.image_id,
    placement_id = self.mark_id,
    row = self.start_row,
    col = self.start_col,
  })
  self.is_displayed = true
end

function Mark:is_alive()
  return self.is_valid
end

function Mark:set_visible(visible)
  if self.is_displayed == visible then
    return
  end

  if self.is_displayed and not visible then
    self:free()
  end
  if not self.is_displayed and visible then
    self:display()
  end

  self.is_displayed = visible
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
      local extmark_id = vim.api.nvim_buf_set_extmark(self.bufnr, NS_ID, self.start_row - 1 + i, self.start_col, {
        virt_text = { { line, self.color_name } },
        virt_text_pos = "overlay",
        virt_text_hide = true,
      })
      self.extmark_ids[#self.extmark_ids + 1] = extmark_id
    end
    self.overlay_ready = true
  end)
end

return Mark
