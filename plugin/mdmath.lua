local subcommands = { "enable", "disable", "build" }

vim.api.nvim_create_user_command("Mdmath",
  function(opts)
    local cmd = opts.fargs[1]
    if not vim.tbl_contains(subcommands, cmd) then
      vim.notify("[MDMATH] Invalid subcommand: " .. cmd, vim.log.levels.ERROR)
      return
    end
    require("mdmath")[cmd]()
  end,
  {
    nargs = 1,
    complete = function()
      return subcommands
    end,
  }
)
