local M = {}

local default_opts = require("mdmath.constants").default_opts

M.opts = default_opts
M.is_loaded = false

local function is_hex_color(text)
  return text:match("^#%x%x%x%x%x%x$")
end

local function hl_as_hex(color)
  if is_hex_color(color) then
    return color:lower()
  end
  local foreground = vim.api.nvim_get_hl(0, { name = color, create = false, link = false }).fg
  return string.format("#%06x", foreground)
end

function M.set_options(opts)
  if M.is_loaded then
    error("[MDMATH] Attempt to setup mdmath.nvim multiple times")
    return
  end

  M.opts = vim.tbl_extend("force", default_opts, opts or {})
  M.opts.foreground = hl_as_hex(M.opts.foreground)

  assert(type(M.opts.filetypes) == "table", "[MDMATH] 'filetypes' config expected list")
  assert(type(M.opts.foreground) == "string", "[MDMATH] 'foreground' config expected string")
  assert(type(M.opts.insert_strategy) == "string", "[MDMATH] 'foreground' config expected string")
  assert(type(M.opts.normal_strategy) == "string", "[MDMATH] 'foreground' config expected string")
  assert(type(M.opts.center_display) == "boolean", "[MDMATH] 'center_display' config expected boolean")
  assert(type(M.opts.center_inline) == "boolean", "[MDMATH] 'center_inline' config expected boolean")
  assert(type(M.opts.pixel_padding) == "number", "[MDMATH] 'pixel_padding' config expected number")
  assert(type(M.opts.bottom_line_ratio) == "number", "[MDMATH] 'bottom_line_ratio' config expected number")
  assert(type(M.opts.retry_mark_draw) == "number", "[MDMATH] 'retry_mark_draw' config expected number")

  assert(#M.opts.filetypes > 0, "[MDMATH] 'filetypes' config expected at least one item")
  assert(is_hex_color(M.opts.foreground), "[MDMATH] 'foreground' config expected valid hl or hex color")
  assert(M.opts.pixel_padding >= 0, "[MDMATH] 'pixel_padding' config expected zero or positive number")
  local pixel_padding_is_integer = M.opts.pixel_padding == math.floor(M.opts.pixel_padding)
  assert(pixel_padding_is_integer, "[MDMATH] 'pixel_padding' config expected integer number")
  local bottom_line_in_range = 0.00 <= M.opts.bottom_line_ratio and M.opts.bottom_line_ratio <= 0.2
  assert(bottom_line_in_range, "[MDMATH] 'bottom_line_ratio' config expected in [0.0, 0.2] interval")
  assert(M.opts.retry_mark_draw > 0, "[MDMATH] 'retry_mark_draw' config expected positive number")
  local display_strategies = {
    hide_all = true,
    show_all = true,
    hide_in_cursor = true,
    hide_in_line = true,
  }
  assert(display_strategies[M.opts.insert_strategy], "[MDMATH] 'insert_strategy' unexpected value")
  assert(display_strategies[M.opts.normal_strategy], "[MDMATH] 'normal_strategy' unexpected value")

  M.is_loaded = true
end

return M
