Buffer = {}

local Equation = require("mdmath.Equation")
local Processor = require("mdmath.Processor")
local Mark = require("mdmath.Mark")
local config = require("mdmath.config").opts
local terminfo = require("mdmath.terminfo")
local augroup = vim.api.nvim_create_augroup("MdmathManager", { clear = true })
local buffers = {}

local function get_parser(bufnr, lang)
  local parser = vim.treesitter.get_parser(bufnr, lang)
  if not parser then
    error("[MDMATH] Parser not found for " .. lang, 2)
  end
  return parser
end

local function hash_equation(equation)
  return vim.fn.system("sha256sum", equation):sub(1, 16)
end

local function get_line_range()
  local first_line = vim.fn.line("w0") - 1
  local last_line = vim.fn.line("w$")
  return first_line, last_line
end

local function get_cursor(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid or 0)
  return cursor[1] - 1, cursor[2]
end

function Buffer.enable_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~=0 and bufnr or vim.api.nvim_get_current_buf()
  if buffers[bufnr] then
    return
  end
  buffers[bufnr] = Buffer:new(bufnr)
end

function Buffer.disable_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~=0 and bufnr or vim.api.nvim_get_current_buf()
  local buffer = buffers[bufnr]
  buffer:free()
  buffers[bufnr] = nil
end

function Buffer:new(bufnr)
  local buffer = {}
  setmetatable(buffer, { __index = self })

  buffer.bufnr = bufnr
  buffer.equations = {}
  buffer.marks = {}
  buffer.parser = get_parser(bufnr, "markdown")
  buffer.tty = vim.uv.new_tty(1, false)
  buffer.timer = vim.uv.new_timer()
  buffer.processor = Processor:new(
    function(data)
      local iter = data:gmatch("([a-zA-Z0-9-/.]*):([a-zA-Z0-9-/.]*):([a-zA-Z0-9-/.]*):")
      for code, hash, value in iter do
        if code == "image" then
          local equation = buffer.equations[hash]
          equation:set_image_path(value)
          equation:transfer_image()
        elseif code == "error" then
          print(data)
        end
      end
    end
  )
  buffer.active = true
  buffer.visible = true
  buffer.mark_counter_id = 1

  -- attach to buf
  vim.api.nvim_buf_attach(buffer.bufnr, false, {
    on_bytes = function(_, _, _,
                        start_row, start_col, start_offset,
                        old_end_row, old_end_col, old_offset,
                        new_end_row, new_end_col, new_offset
    )
      --relative to absolute
      local opts = {}
      opts.start_row = start_row
      opts.start_col = start_col
      opts.start_offset = start_offset

      opts.old_end_row = old_end_row + start_row
      opts.old_end_col = old_end_row == start_row and old_end_col + start_col or old_end_col

      opts.new_end_row = new_end_row + start_row
      opts.new_end_col = new_end_row == start_row and new_end_col + start_col or new_end_col

      opts.old_offset = old_offset + start_offset
      opts.new_offset = new_offset + start_offset

      for key, mark in pairs(buffer.marks) do
        mark:update_position(opts)
        if not mark:is_alive() then
          buffer.marks[key]:free()
          buffer.marks[key] = nil
        end
      end
    end,
    on_lines = function() buffer:reset_timer() end
  })

  -- create autocmds
  vim.api.nvim_create_autocmd({ "VimLeave" }, {
    buffer = buffer.bufnr,
    group = augroup,
    callback = function()
      buffer:free()
    end
  })
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    callback = function()
      vim.schedule(function()
        terminfo.refresh_terminal()
        buffer.processor:set_cell_sizes()
        buffer:_free_equations()
        buffer:_free_marks()
        buffer:reset_timer()
      end)
    end
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave" }, {
    buffer = buffer.bufnr,
    group = augroup,
    callback = function()
      buffer:reset_timer()
    end
  })
  vim.api.nvim_create_autocmd({ "WinScrolled" }, {
    buffer = buffer.bufnr,
    group = augroup,
    callback = function()
      buffer:reset_timer()
    end
  })
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = buffer.bufnr,
    group = augroup,
    callback = function()
      buffer:_cursor_move()
    end
  })
  vim.api.nvim_create_autocmd({ "ModeChanged" }, {
    buffer = buffer.bufnr,
    group = augroup,
    callback = function()
      local old_mode = vim.v.event.old_mode:sub(1, 1)
      local mode = vim.v.event.new_mode:sub(1, 1)
      if old_mode == mode then
        return
      end
      if config.hide_on_insert and (mode == "i" or mode == "R") then
        for _, mark in pairs(buffer.marks) do
          mark:set_visible(false)
        end
      end
    end
  })

  return buffer
end

function Buffer:free()
  if not self.active then
    return
  end
  self.active = false
  self.visible = false
  self:_free_equations()
  self:_free_marks()
  self.processor:free()
  buffers[self.bufnr] = nil

  vim.api.nvim_clear_autocmds({
    group = augroup,
    buffer = self.bufnr
  })
end

function Buffer:loop()
  self:_parse_line_range()
  self:_process_image_equations()
  self:_draw_marks()
end

function Buffer:reset_timer()
  self.timer:start(config.update_interval, 0, vim.schedule_wrap(function()
    self:loop()
  end))
end

function Buffer:_cursor_move()
  if not config.anticonceal then
    return
  end
  local row, col = get_cursor()
  local cursor_offset = Mark.compute_offset(self.bufnr, row, col)
  for _, mark in pairs(self.marks) do
    local visible = not mark:contains_offset(cursor_offset)
    mark:set_visible(visible)
  end
end

function Buffer:_free_equations()
  for _, equation in ipairs(self.equations) do
    equation:free()
  end
  self.equations = {}
end

function Buffer:_free_marks()
  for _, mark in pairs(self.marks) do
    mark:free()
  end
  self.marks = {}
end

function Buffer:_parse_line_range()
  local first_row, last_row = get_line_range()
  self.parser:parse({ first_row, last_row })
  local inlines = self.parser:children()["markdown_inline"]
  if not inlines then
    return
  end

  local inline_query = vim.treesitter.query.parse("markdown_inline", "(latex_block) @block")
  local new_locations = {}
  inlines:for_each_tree(function(tree)
    for _, node, _, _ in inline_query:iter_captures(tree:root(), 0, first_row, last_row) do
      local start_row, start_col, end_row, end_col = node:range()
      local text = vim.treesitter.get_node_text(node, 0)
      local hash = hash_equation(text)
      if not self.equations[hash] then
        local equation = Equation:new({
          hash = hash,
          bufnr = self.bufnr,
          text = text,
          inline = true,
          tty = self.tty
        })
        self.equations[hash] = equation
      end
      new_locations[hash] = new_locations[hash] or {}
      new_locations[hash][#new_locations[hash] + 1] = {
        start_row = start_row, start_col = start_col,
        end_row = end_row, end_col = end_col,
      }
    end
  end)
  for equation_hash, locations in pairs(new_locations) do
    for _, loc in ipairs(locations) do
      local mark = self.equations[equation_hash]:create_new_mark({
        mark_id = self.mark_counter_id,
        start_row = loc.start_row,
        start_col = loc.start_col,
        end_row = loc.end_row,
        end_col = loc.end_col,
      })
      if mark then
        self.marks[tostring(self.mark_counter_id)] = mark
        self.mark_counter_id = self.mark_counter_id + 1
      end
    end
  end
  local i = 0
  for _, _ in pairs(self.marks) do
    i = i + 1
  end
  print(i)
end

function Buffer:_process_image_equations()
  for _, equation in pairs(self.equations) do
    equation:request_image_mathjax(self.processor)
  end
end

function Buffer:_draw_marks()
  for _, mark in pairs(self.marks) do
    mark:display()
  end
end

return Buffer
