local Equation = {}
Equation.__index = Equation

local EQUATION_TYPE = {
  IMAGE = 1,
  ERROR = 2
}

local EQUATION_MODE = {
  INLINE = 1,
  DISPLAY = 2,
  NONE = 3,
}

local hl = require("mdmath.highlight_colors")
local Mark = require("mdmath.mark")
local kitty = require("mdmath.kitty")
local utils = require("mdmath.utils")
local terminfo = require("mdmath.terminfo")
local config = require("mdmath.config").opts
local equation_strategies = require("mdmath.equation_strategies")
EQUATION_ID = 500

local function _get_id()
  EQUATION_ID = EQUATION_ID + 1
  return EQUATION_ID
end

function Equation.new(opts)
  local self = {}
  setmetatable(self, Equation)

  self.id = _get_id()
  self.buffer = opts.buffer
  self.hash = opts.hash
  self.text = opts.text
  self.equation_strategy = nil

  self.equation = opts.text:gsub("^%$*(.-)%$*$", "%1"):gsub("[\n\r]", "")
  self:_set_equation_mode()
  self.equation_type = nil
  self.is_displayable = false
  self.image_filename = nil
  self.marks = {}
  self.mark_strategy = nil
  self.show_function = nil
  self.hide_equation = nil

  local lines = utils.equation.split_text_in_lines(opts.text)
  local lines_width = {}
  for _, line in pairs(lines) do
    lines_width[#lines_width+1] = line:len()
  end
  self.color_name = hl.register_color_as_highlight(self.id)
  self.ncells_w = math.max(unpack(lines_width))
  self.ncells_h = #lines
  return self
end

function Equation:free()
  kitty.delete_image({
    tty = self.buffer:get_tty(),
    image_id = self.id,
  })
  for _, mark in pairs(self.marks) do
    mark:free()
  end
  self.buffer:remove_equation(self)
end

function Equation:get_hash()
  return self.hash
end

function Equation:get_id()
  return self.id
end

function Equation:request_image_mathjax(processor)
  if not self.is_displayable then
    processor:request_image({
      hash = self.hash,
      equation = self.equation,
      numberCellsWidth = self.ncells_w,
      numberCellsHeight = self.ncells_h,
      equationType = self.equation_mode == EQUATION_MODE.INLINE and "inline" or "display",
    })
  end
end

function Equation:remove_mark(mark)
  self.marks[mark:get_hash()] = nil
end

---@param opts {
  ---mark_id: number,
  ---start_row: number,
  ---start_col: number,
  ---end_row: number,
  ---end_col: number,
  ---}
function Equation:get_or_create_mark(opts)
  local found_mark = nil
  for _, mark in pairs(self.marks) do
    if mark:is_location(opts.start_row, opts.start_col) then
      found_mark = mark
      break
    end
  end
  if found_mark then
    return found_mark, true
  end
  local mark = Mark.new({
    equation = self,
    buffer = self.buffer,
    color_name = self.color_name,
    ncells_w = self.ncells_w,
    ncells_h = self.ncells_h,
    start_row = opts.start_row,
    start_col = opts.start_col,
    end_row = opts.end_row,
    end_col = opts.end_col,
  })
  self.marks[mark:get_hash()] = mark
  return mark, false
end

function Equation:is_message()
  return self.message
end

function Equation:get_message()
  return self.message
end

function Equation:get_dimensions()
  local pixels_per_cell_w, pixels_per_cell_h = terminfo.get_pixels_per_cell()
  return {
    npixel_w = self.image_width,
    npixel_h = self.image_height,
    ncells_w = math.ceil(self.image_width / pixels_per_cell_w),
    ncells_h = math.ceil(self.image_height / pixels_per_cell_h),
  }
end

function Equation:set_processor_result(event)
  if event.type == "image" then
    self.equation_type = EQUATION_TYPE.IMAGE
    self.image_filename = event.filename
    self.image_width = event.imageWidth
    self.image_height = event.imageHeight
    self:_transfer_png_file()
    self.is_displayable = true
  elseif event.type == "error" then
    self.equation_type = EQUATION_TYPE.ERROR
    self.message = event.error
    self.is_displayable = true
  end
end

function Equation:show_mark(mark)
  if not self.is_displayable then
    vim.defer_fn(function()
      self:show_mark(mark)
    end, config.retry_mark_draw)
    return
  end
  local strategy = self:_get_mark_strategy()
  strategy.create_extmarks(mark, self, self.buffer)
  strategy.show(mark, self, self.buffer)
end

function Equation:hide_mark(mark)
  if not self.is_displayable then
    vim.defer_fn(function()
      self:hide()
    end, config.retry_mark_draw)
    return
  end
  local strategy = self:_get_mark_strategy()
  strategy.hide(mark, self, self.buffer)
end

function Equation:_set_equation_mode()
  if self.text:sub(1, 2) == "$$" and self.text:sub(-2) == "$$" then
    self.equation_mode = EQUATION_MODE.DISPLAY
  elseif self.text:sub(1, 2) == "\\[" and self.text:sub(-2) == "\\]" then
    self.equation_mode = EQUATION_MODE.DISPLAY
  elseif self.text:sub(1, 1) == "$" and self.text:sub(-1) == "$" then
    self.equation_mode = EQUATION_MODE.INLINE
  else
    self.equation_mode = EQUATION_MODE.NONE
  end
end

function Equation:_transfer_png_file()
  kitty.transfer_png_file({
    tty = self.buffer:get_tty(),
    png_path = self.image_filename,
    image_id = self.id
  })
end

function Equation:_get_mark_strategy()
  if self.equation_strategy then
    return self.equation_strategy
  end
  if self.equation_type == EQUATION_TYPE.ERROR then
    self.equation_strategy = equation_strategies["ErrorStrategy"]
    return self.equation_strategy
  elseif self.equation_type == EQUATION_TYPE.IMAGE then
    if self.equation_mode == EQUATION_MODE.INLINE then
      self.equation_strategy = equation_strategies[config.inline_strategy]
      return self.equation_strategy
    elseif self.equation_mode == EQUATION_MODE.DISPLAY then
      self.equation_strategy = equation_strategies["AdjustEquationToText"]
      return self.equation_strategy
    end
  end
end

return Equation
