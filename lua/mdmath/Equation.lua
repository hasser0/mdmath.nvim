Equation = {}
Equation.__index = Equation

local EQUATION_TYPE = {
  INLINE = 1,
  DISPLAY = 2,
  NONE = 3,
}

local hl = require("mdmath.highlight_colors")
local kitty = require("mdmath.kitty")
local config = require("mdmath.config").opts
local Mark = require("mdmath.Mark")
EQUATION_ID = 500

local function _get_id()
  EQUATION_ID = EQUATION_ID + 1
  return EQUATION_ID
end

local function split_text_in_lines(text)
  local lines
  if text:find("\n") then
    lines = vim.split(text, "\n")
  else
    lines = { text }
  end
  return lines
end

function Equation.hash_equation(equation)
  return vim.fn.system("sha256sum", equation):sub(1, 16)
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

  local lines = split_text_in_lines(opts.text)
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
      ncells_w = self.ncells_w,
      ncells_h = self.ncells_h,
      inline = self.equation_type == EQUATION_TYPE.INLINE and 1 or 0,
      flags = self:_get_flags(),
      color = config.foreground,
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
  return self.message ~= nil
end

function Equation:get_message()
  return self.message
end

function Equation:set_message(msg)
  self.message = msg
  self.is_displayable = true
end

function Equation:set_image_path(path)
  self.image_filename = path
  if not self.is_displayable then
    kitty.transfer_png_file({
      tty = self.buffer:get_tty(),
      png_path = self.image_filename,
      image_id = self.id
    })
    self.is_displayable = true
  end
end

function Equation:_get_flags()
  local flags = 0
  if (self.equation_type == EQUATION_TYPE.DISPLAY and config.center_display) or
    (self.equation_type == EQUATION_TYPE.INLINE and config.center_inline) then
    flags = flags + 2
  end
  if self.equation_type == EQUATION_TYPE.INLINE then
    flags = flags + 4
  end
  return flags
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
