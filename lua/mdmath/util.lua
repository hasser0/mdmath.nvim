local M = {}

function M.class(name)
  local class = {}
  class.__index = class
  class.__name = name
  class.new = function(...)
    local self = setmetatable({}, class)
    if self._init then
      if self:_init(...) == false then
        return nil
      end
    end
    return self
  end
  return class
end

function M.get_cursor(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid or 0)
  return cursor[1] - 1, cursor[2]
end

function M.get_line_width(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  return line and line[1]:len() or 0
end

function M.get_buffer_offset(bufnr, row, col)
  local row_offset = vim.api.nvim_buf_get_offset(bufnr, row)
  if row_offset == -1 then
    return nil
  end
  -- TODO check whether encoding affects
  local line_width = M.get_line_width(bufnr, row)
  local col_offset = line_width < col and line_width or col
  return row_offset + col_offset
end

function M.get_line_range()
  local first_line = vim.fn.line("w0") - 1
  local last_line = vim.fn.line("w$")
  return first_line, last_line
end

function M.get_string_width(text)
  return vim.fn.strdisplaywidth(text)
end

function M.notify_error(...)
  local message = table.concat(vim.iter({ ... }):flatten():totable())
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.notify("mdmath.nvim: " .. message, vim.log.levels.ERROR)
    end)
  else
    vim.notify("mdmath.nvim: " .. message, vim.log.levels.ERROR)
  end
end

function M.is_hex_color(color)
  return color:match("^#%x%x%x%x%x%x$") ~= nil
end

function M.hl_as_hex(color)
  if M.is_hex_color(color) then
    return color:lower()
  end
  local foreground = vim.api.nvim_get_hl(0, { name = color, create = false, link = false }).fg
  return string.format("#%06x", foreground)
end

return M
