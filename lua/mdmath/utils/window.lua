local M = {}

function M.get_line_range()
  local first_line = vim.fn.line("w0") - 1
  local last_line = vim.fn.line("w$")
  return first_line, last_line
end

function M.get_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] - 1, cursor[2]
end

return M
