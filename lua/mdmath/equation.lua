local Equation = {}
Equation.__index = Equation

local EQUATION_TYPE = {
  INLINE = 1,
  DISPLAY = 2,
  NONE = 3,
}

local hl = require("mdmath.highlight_colors")
local Mark = require("mdmath.mark")
local kitty = require("mdmath.kitty")
local config = require("mdmath.config").opts
local utils = require("mdmath.utils")
local terminfo = require("mdmath.terminfo")
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

  self.equation = opts.text:gsub("^%$*(.-)%$*$", "%1"):gsub("[\n\r]", "")
  self.equation_type = self:_get_equation_type()
  self.is_displayable = false
  self.image_filename = nil
  self.marks = {}
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
      ncellsWidth = self.ncells_w,
      ncellsHeight = self.ncells_h,
      equationType = self.equation_type == EQUATION_TYPE.INLINE and "inline" or "display",
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
function Equation:create_new_mark(opts)
  local already_exists = false
  for _, mark in pairs(self.marks) do
    already_exists = already_exists or mark:is_location(opts.start_row, opts.start_col)
  end
  if already_exists then
    return nil
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
  return mark
end

function Equation:is_ready()
  return self.is_displayable
end

function Equation:is_message()
  return self.message
end

function Equation:get_message()
  return self.message
end

function Equation:get_dimensions()
  local pixels_per_cell_w, pixels_per_cell_h = terminfo.get_pixels_per_cell()
  print(self.image_width, pixels_per_cell_w)
  return {
    ncells_w = math.ceil(self.image_width / pixels_per_cell_w),
    ncells_h = math.ceil(self.image_height / pixels_per_cell_h),
  }
end

function Equation:set_processor_result(event)
  if event.type == "image" then
    self.image_filename = event.filename
    self.image_width = event.imageWidth
    self.image_height = event.imageHeight
    kitty.transfer_png_file({
      tty = self.buffer:get_tty(),
      png_path = self.image_filename,
      image_id = self.id
    })
    self.hide_function = equation_strategies["hide_equation"]
    if self.equation_type == EQUATION_TYPE.INLINE then
      self.show_function = equation_strategies[config.inline_strategy_show]
    elseif self.equation_type == EQUATION_TYPE.DISPLAY then
      self.show_function = equation_strategies["show_overlay"]
    end
  elseif event.type == "error" then
    self.message = event.error
    self.show_function = equation_strategies["show_error"]
    self.hide_function = equation_strategies["hide_error"]
  end
  self.is_displayable = true
end

function Equation:show(mark, equation, buffer)
  self.show_function(mark, equation, buffer)
end

function Equation:hide(mark, equation, buffer)
  self.hide_function(mark, equation, buffer)
end

function Equation:_get_equation_type()
  if self.equation_type then
    return self.equation_type
  end

  if self.text:sub(1, 2) == "$$" and self.text:sub(-2) == "$$" then
    self.equation_type = EQUATION_TYPE.DISPLAY
  elseif self.text:sub(1, 2) == "\\[" and self.text:sub(-2) == "\\]" then
    self.equation_type = EQUATION_TYPE.DISPLAY
  elseif self.text:sub(1, 1) == "$" and self.text:sub(-1) == "$" then
    self.equation_type = EQUATION_TYPE.INLINE
  else
    self.equation_type = EQUATION_TYPE.NONE
  end
  return self.equation_type
end

return Equation
