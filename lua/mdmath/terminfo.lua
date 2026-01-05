local M = {}
local ffi = require("ffi")

M.winsize = nil

ffi.cdef [[
  struct mdmath_winsize {
      unsigned short int ws_row;
      unsigned short int ws_col;
      unsigned short int ws_xpixel;
      unsigned short int ws_ypixel;
  };
  int ioctl(int fd, unsigned long op, ...);
]]

local function request_terminal_measures()
  local tiocgwinsz
  -- Based on hologram.nvim
  if vim.fn.has("linux") == 1 then
    tiocgwinsz = 0x5413
  elseif vim.fn.has("mac") == 1 then
    tiocgwinsz = 0x40087468
  elseif vim.fn.has("bsd") == 1 then
    tiocgwinsz = 0x40087468
  else
    error("mdmath.nvim: Unsupported platform, please report this issue")
  end

  ---@class ffi.cdata*
  ---@field ws_row number
  ---@field ws_col number
  ---@field ws_xpixel number
  ---@field ws_ypixel number
  local ws = ffi.new("struct mdmath_winsize")
  if ffi.C.ioctl(1, tiocgwinsz, ws) < 0 then
    return nil, ffi.errno()
  end

  return {
    row = ws.ws_row,
    col = ws.ws_col,
    xpixel = ws.ws_xpixel,
    ypixel = ws.ws_ypixel
  }
end

local function create_autocmd()
  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      M.refresh()
    end
  })
end

if vim.in_fast_event() then
  vim.schedule(create_autocmd)
else
  create_autocmd()
end

function M.get_window_size()
  local err = nil
  if M.winsize == nil then
    M.winsize, err = request_terminal_measures()
    if not M.winsize then
      error("Failed to get terminal size: code " .. err)
    end
  end
  return M.winsize
end

function M.get_cell_size()
  local size = M.get_window_size()
  local width = size.xpixel / size.col
  local height = size.ypixel / size.row
  return width, height
end

function M.refresh()
  M.winsize = nil
end

return M
