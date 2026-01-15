M = {}

local group = vim.api.nvim_create_augroup("Mdmath", { clear = true })

function M.setup(opts)
  require("mdmath.config").set_options(opts)
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = M.opts.filetypes,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      require("mdmath.Buffer").enable_mdmath_for_buffer(bufnr)
    end,
  })
end

function M.enable(bufnr)
  require("mdmath.Buffer").enable_mdmath_for_buffer(bufnr or 0)
end

function M.disable(bufnr)
  require("mdmath.Buffer").disable_mdmath_for_buffer(bufnr or 0)
end

function M.build()
  require("mdmath.build").build()
end

return M
