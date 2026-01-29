local M = {}

local group = vim.api.nvim_create_augroup("Mdmath", { clear = true })

function M.setup(opts)
  require("mdmath.config").set_options(opts)
  vim.api.nvim_create_autocmd({ "VimEnter", "WinNew" }, {
    group = group,
    callback = function(args)
      require("mdmath.window").enable_mdmath_for_window()
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    pattern = { "*.md", "*.tex" },
    group = group,
    callback = function(args)
      local winid = vim.api.nvim_get_current_win()
      require("mdmath.window").attach_buffer_to_window(args.buf, winid)
    end
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    pattern = { "*.md", "*.tex" },
    group = group,
    callback = function(args)
      local winid = vim.api.nvim_get_current_win()
      require("mdmath.window").detach_buffer_from_window(args.buf, winid)
    end
  })

end

function M.enable()
  require("mdmath.window").enable_mdmath_for_window()
end

function M.disable()
  require("mdmath.window").disable_mdmath_for_window()
end

function M.clear()
  require("mdmath.window").clear_mdmath_for_window()
end

function M.build()
  require("mdmath.build").build()
end

return M
