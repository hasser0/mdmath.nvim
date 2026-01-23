local M = {}

---@param opts { tty: any, png_path: string, image_id: number }
function M.transfer_png_file(opts)
  local tty_image_id = string.format("i=%d", opts.image_id)
  opts.tty:write(
    string.format(
      "\x1b_G%s,f=100,t=f,q=1,q=2;%s\x1b\\",
      tty_image_id,
      vim.base64.encode(opts.png_path)
    )
  )
end

---@param opts { tty: any, placement_id: number, image_id: number, row: number, col: number  }
function M.display_image_placement(opts)
  local tty_image_id = string.format("i=%d", opts.image_id)
  local row_col = string.format("X=%d,Y=%d", opts.row, opts.col)
  local tty_placement_id = string.format("p=%d", opts.placement_id)
  opts.tty:write(string.format("\x1b_G%s,U=1,a=p,q=1,q=2,%s,%s\x1b\\", tty_image_id, row_col, tty_placement_id))
end

---@param opts { tty: any, placement_id: number, image_id: number }
function M.delete_image_placement(opts)
  local tty_image_id = string.format("i=%d", opts.image_id)
  local tty_placement_id = string.format("p=%d", opts.placement_id)
  opts.tty:write(string.format("\x1b_G%s,a=d,d=i,%s,q=1,q=2\x1b\\", tty_image_id, tty_placement_id))
end

---@param opts { tty: any, image_id: number }
function M.delete_image(opts)
  local tty_image_id = string.format("i=%d", opts.image_id)
  opts.tty:write(string.format("\x1b_G%s,a=d,d=I,q=1,q=2\x1b\\", tty_image_id))
end

return M
