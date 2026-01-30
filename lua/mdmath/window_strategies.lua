local M = {}

local utils = require("mdmath.utils")

function M.hide_in_cursor(window, marks)
  local row, col = window:get_cursor()
  local cursor_offset = utils.mark.compute_offset(window:get_bufnr(), row, col)
  for _, mark in pairs(marks) do
    local mark_in_cursor = mark:contains_offset(cursor_offset)
    if mark_in_cursor then
      mark:hide()
    else
      mark:show()
    end
  end
end

function M.hide_in_line(window, marks)
  local row, _ = window:get_cursor()
  for _, mark in pairs(marks) do
    local mark_inline = mark:contains_row(row)
    if mark_inline then
      mark:hide()
    else
      mark:show()
    end
  end
end

function M.hide_all(window, marks)
  for _, mark in pairs(marks) do
    mark:hide()
  end
end

function M.show_all(window, marks)
  for _, mark in pairs(marks) do
    mark:show()
  end
end

return M
