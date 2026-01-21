local M = {}

function M.hash_mark(id)
  return tostring(id)
end

function M.linewidth(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  return line and line[1]:len() or 0
end

function M.compute_offset(bufnr, row, col)
  local row_offset = vim.api.nvim_buf_get_offset(bufnr, row)
  if row_offset == -1 then
    return nil
  end

  local len = M.linewidth(bufnr, row)
  local col_offset = len < col and len or col
  return row_offset + col_offset
end

return M
