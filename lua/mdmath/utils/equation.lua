local M = {}

function M.split_text_in_lines(text)
  local lines
  if text:find("\n") then
    lines = vim.split(text, "\n")
  else
    lines = { text }
  end
  return lines
end

function M.hash_equation(equation)
  return vim.fn.system("sha256sum", equation):sub(1, 16)
end

return M
