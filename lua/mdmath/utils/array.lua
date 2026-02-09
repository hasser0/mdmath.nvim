M = {}

function M.contains(arr, value)
  local found = false
  for _, v in ipairs(arr) do
    if v == value then
      found = true
      break
    end
  end
  return found
end

return M
