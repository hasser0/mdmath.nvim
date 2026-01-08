Equation = {}

local EQUATION_TYPE = {
  INLINE = 1,
  DISPLAY = 2,
  NONE = 3,
}

local hl = require("mdmath.highlight_colors")
local kitty = require("mdmath.kitty")
local config = require("mdmath.config").opts
local Mark = require("mdmath.Mark")
ID = 500

local function get_id()
  ID = ID + 1
  return ID
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

function Equation:new(opts)
  local eq = {}
  setmetatable(eq, { __index = self })

  eq.bufnr = opts.bufnr
  eq.hash = opts.hash
  eq.id = get_id()
  eq.filename_ready = false
  eq.transfered = false
  eq.tty = opts.tty
  eq.text = opts.text
  eq.equation = opts.text:gsub("^%$*(.-)%$*$", "%1"):gsub("[\n\r]", "")
  eq:_set_equation_type()
  eq.image_filename = nil
  eq.marks = {}

  local lines = split_text_in_lines(opts.text)
  local lines_width = {}
  for _, line in pairs(lines) do
    lines_width[#lines_width+1] = line:len()
  end
  eq.color_name = hl.register_color_as_highlight(eq.id)
  eq.ncells_w = math.max(unpack(lines_width))
  eq.ncells_h = #lines
  return eq
end

function Equation:free()
  kitty.delete_image({
    tty = self.tty,
    image_id = self.id,
  })
end

function Equation:request_image_mathjax(processor)
  if not self.filename_ready then
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
  local mark = Mark:new({
    mark_id = opts.mark_id,
    bufnr = self.bufnr,
    color_name = self.color_name,
    ncells_w = self.ncells_w,
    ncells_h = self.ncells_h,
    image_id = self.id,
    start_row = opts.start_row,
    start_col = opts.start_col,
    end_row = opts.end_row,
    end_col = opts.end_col,
    tty = self.tty,
    callback = function()
      return self.transfered
    end
  })
  self.marks[tostring(opts.mark_id)] = mark
  return mark
end

function Equation:transfer_image()
  if self.filename_ready and not self.transfered then
    self.transfered = true
    kitty.transfer_png_file({
      tty = self.tty,
      png_path = self.image_filename,
      image_id = self.id
    })
  end
end

function Equation:set_image_path(text)
  self.image_filename = text
  self.filename_ready = true
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

function Equation:_set_equation_type()
  if self.text:sub(1, 2) == "$$" and self.text:sub(-2) == "$$" then
    self.equation_type = EQUATION_TYPE.DISPLAY
  elseif self.text:sub(1, 2) == "\\[" and self.text:sub(-2) == "\\]" then
    self.equation_type = EQUATION_TYPE.DISPLAY
  elseif self.text:sub(1, 1) == "$" and self.text:sub(-1) == "$" then
    self.equation_type = EQUATION_TYPE.INLINE
  else
    self.equation_type = EQUATION_TYPE.NONE
  end
end

return Equation
