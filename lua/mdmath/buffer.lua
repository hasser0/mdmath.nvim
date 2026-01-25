local Buffer = {}
Buffer.__index = Buffer

local Equation = require("mdmath.equation")
local Processor = require("mdmath.processor")
local buffer_strategies = require("mdmath.buffer_strategies")
local config = require("mdmath.config").opts
local utils = require("mdmath.utils")
local terminfo = require("mdmath.terminfo")
local augroup = vim.api.nvim_create_augroup("MdmathManager", { clear = true })
local buffers = {}

local BUFFER_MODE = {
  INSERT = 1,
  NORMAL = 2,
}

local function _get_parser(bufnr, lang)
  local language_map = {
    markdown = "markdown",
    tex = "latex",
  }
  local parser = vim.treesitter.get_parser(bufnr, language_map[lang])
  if not parser then
    error("[MDMATH] Parser not found for " .. lang, 2)
  end
  return parser
end

local function _debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local argv = {...}
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(argv))
    end))
  end
end

function Buffer.enable_mdmath_for_buffer(bufnr)
  local filetype = vim.bo.filetype
  bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  if buffers[bufnr] then
    return
  end
  buffers[bufnr] = Buffer.new(bufnr, filetype)
end

function Buffer.disable_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  local buffer = buffers[bufnr]
  buffer:free()
  buffers[bufnr] = nil
end

function Buffer.clear_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  buffers[bufnr]:free_equations()
end

function Buffer.new(bufnr, filetype)
  local self = {}

  setmetatable(self, Buffer)
  self.insert_display = buffer_strategies[config.insert_strategy]
  self.normal_display = buffer_strategies[config.normal_strategy]

  self.bufnr = bufnr
  self.filetype = filetype
  self.mode = BUFFER_MODE.NORMAL
  self.equations = {}
  self.marks = {}
  self.parser = _get_parser(bufnr, filetype)
  self.tty = vim.uv.new_tty(1, false)
  self.active = true

  self.processor = Processor.new(self)

  -- TODO remove
  -- attach to buf
  -- vim.api.nvim_buf_attach(self.bufnr, false, {
  --   on_bytes = function(_, _, _,
  --                       start_row, start_col, start_offset,
  --                       old_end_row, old_end_col, old_offset,
  --                       new_end_row, new_end_col, new_offset)
  --     self:_autocmd_update_bytes(_, _, _, start_row, start_col, start_offset,
  --       old_end_row, old_end_col, old_offset,
  --       new_end_row, new_end_col, new_offset)
  --   end,
  -- })

  -- create autocmds
  vim.api.nvim_create_autocmd({ "VimLeave", "BufLeave" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = function(args)
      self:free()
    end
  })
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    callback = _debounce(function(args)
      terminfo.refresh_terminal()
      self.processor:set_cell_sizes()
      self:free_equations()
      self:_loop()
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = _debounce(function(args)
      self:_loop()
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = _debounce(function(args)
      self:normal_display(self.marks)
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "ModeChanged" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = function(args)
      local old_mode = vim.v.event.old_mode:sub(1, 1)
      local mode = vim.v.event.new_mode:sub(1, 1)
      -- Mode is the same when deleting char with "x"
      if old_mode == mode then
        return
      end
      self:_autocmd_update_mode(old_mode, mode)
      self:_loop()
    end
  })

  return self
end

function Buffer:free()
  if not self.active then
    return
  end
  self.active = false
  self:free_equations()
  self.processor:free()
  buffers[self.bufnr] = nil

  vim.api.nvim_clear_autocmds({
    group = augroup,
    buffer = self.bufnr
  })
end

function Buffer:get_bufnr()
  return self.bufnr
end

function Buffer:get_tty()
  return self.tty
end

function Buffer:notify_processor(event)
  if event.hash then
    self.equations[event.hash]:set_processor_result(event)
  end
end

function Buffer:remove_mark(mark)
  self.marks[mark:get_hash()] = nil
end

function Buffer:remove_equation(equation)
  self.equations[equation:get_hash()] = nil
end

function Buffer:_loop()
  self:_parse_line_range()
  self:_draw()
end

function Buffer:_draw()
  if self.mode == BUFFER_MODE.NORMAL then
    self:normal_display(self.marks)
  elseif self.mode == BUFFER_MODE.INSERT then
    self:insert_display(self.marks)
  end
end

function Buffer:free_equations()
  for _, equation in pairs(self.equations) do
    equation:free()
  end
end

function Buffer:_parse_line_range()
  local first_row, last_row = utils.window.get_line_range()
  self.parser:parse({ first_row, last_row })

  local parser = nil
  local query = nil
  if self.filetype == "markdown" then
    parser = self.parser:children()["markdown_inline"]
    query = vim.treesitter.query.parse("markdown_inline", "(latex_block) @math")
  elseif self.filetype == "tex" then
    parser = self.parser
    query = vim.treesitter.query.parse("latex", [[
      [
        (inline_formula)
        (displayed_equation)
      ] @math
    ]])
  else
    return
  end

  local new_locations = {}
  parser:for_each_tree(function(tree)
    for _, node, _, _ in query:iter_captures(tree:root(), 0, first_row, last_row) do
      local start_row, start_col, end_row, end_col = node:range()
      local text = vim.treesitter.get_node_text(node, 0)
      local hash = utils.equation.hash_equation(text)
      if not self.equations[hash] then
        local equation = Equation.new({
          buffer = self,
          hash = hash,
          text = text,
          tty = self.tty
        })
        self.equations[hash] = equation
        equation:request_image_mathjax(self.processor)
      end
      new_locations[hash] = new_locations[hash] or {}
      new_locations[hash][#new_locations[hash] + 1] = {
        start_row = start_row, start_col = start_col,
        end_row = end_row, end_col = end_col,
      }
    end
  end)
  for _, mark in pairs(self.marks) do
    mark:invalidate()
  end
  for equation_hash, locations in pairs(new_locations) do
    for _, loc in ipairs(locations) do
      local mark, exists = self.equations[equation_hash]:get_or_create_mark({
        start_row = loc.start_row,
        start_col = loc.start_col,
        end_row = loc.end_row,
        end_col = loc.end_col,
      })
      if not exists then
        self.marks[mark:get_hash()] = mark
      else
        mark:validate()
      end
    end
  end
  for _, mark in pairs(self.marks) do
    if not mark:is_alive() then
      mark:free()
    end
  end
end

function Buffer:_autocmd_update_bytes(_, _, _,
                              start_row, start_col, start_offset,
                              old_end_row, old_end_col, old_offset,
                              new_end_row, new_end_col, new_offset
)
  --relative to absolute
  local opts = {}
  opts.start_row = start_row
  opts.old_end_row = old_end_row + start_row
  opts.new_end_row = new_end_row + start_row

  opts.start_col = start_col
  opts.old_end_col = old_end_row == start_row and old_end_col + start_col or old_end_col
  opts.new_end_col = new_end_row == start_row and new_end_col + start_col or new_end_col

  opts.start_offset = start_offset
  opts.old_offset = old_offset + start_offset
  opts.new_offset = new_offset + start_offset

  for key, mark in pairs(self.marks) do
    mark:update_position(opts)
    if not mark:is_alive() then
      self.marks[key]:free()
      self.marks[key] = nil
    end
  end
end

function Buffer:_autocmd_update_mode(old_mode, mode)
  if mode == "i" or mode == "R" then
    self.mode = BUFFER_MODE.INSERT
  elseif mode == "n" then
    self.mode = BUFFER_MODE.NORMAL
  end
end

return Buffer
