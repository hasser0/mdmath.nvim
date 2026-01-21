local M = {}

local MDMATH_HIGHLIGHT_PREFIX = "MdmathHL-"

function M.register_color_as_highlight(color)
  assert(type(color) == "number", "key must be a number")
  assert(1 <= color and color <= 0xFFFFFF, "key must be in a 24-bit color range")
  local name = MDMATH_HIGHLIGHT_PREFIX .. tostring(color)
  vim.api.nvim_command(string.format("highlight %s guifg=#%06X ctermfg=%d", name, color, color))
  return name
end

return M
