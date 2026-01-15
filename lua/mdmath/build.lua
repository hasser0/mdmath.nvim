M = {}

local PLUGIN_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local JS_DIR = PLUGIN_DIR .. "/mdmath-js"

local function exists_dir(file)
  local ok, err, code = os.rename(file, file)
  if not ok then
    if code == 13 then
      return true
    end
  end
  return ok, err
end

function M.build(callback)
  if not callback then
    callback = function() end
  end

  if not exists_dir(JS_DIR) then
    error("[MDMATH]: Dir " .. JS_DIR .. " does not exist")
  end

  local stderr, err = vim.uv.new_pipe(false)
  if not stderr then
    error("[MDMATH] Failed to create stderr pipe on build: " .. err)
    return
  end

  vim.uv.spawn("npm",
    {
      args = { "install" },
      stdio = { _, _, stderr },
      cwd = JS_DIR,
    }
  )
  callback()
end

function M.build_lazy()
    local done = false

    M.build(function()
      done = true
    end)
    while not done do
        coroutine.yield("Building")
    end
    coroutine.yield("Done")
end

return M
