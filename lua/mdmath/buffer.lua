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
  local parser = vim.treesitter.get_parser(bufnr, lang)
  if not parser then
    error("[MDMATH] Parser not found for " .. lang, 2)
  end
  return parser
end

function Buffer.enable_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  if buffers[bufnr] then
    return
  end
  buffers[bufnr] = Buffer.new(bufnr)
end

function Buffer.disable_mdmath_for_buffer(bufnr)
  bufnr = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  local buffer = buffers[bufnr]
  buffer:free()
  buffers[bufnr] = nil
end

function Buffer.new(bufnr)
  local self = {}
  setmetatable(self, Buffer)
  self.insert_display = buffer_strategies[config.insert_strategy]
  self.normal_display = buffer_strategies[config.normal_strategy]

  self.bufnr = bufnr
  self.mode = BUFFER_MODE.NORMAL
  self.equations = {}
  self.marks = {}
  self.parser = _get_parser(bufnr, "markdown")
  self.tty = vim.uv.new_tty(1, false)
  self.timer = vim.uv.new_timer()
  self.active = true

  self.processor = Processor.new(self)

  -- attach to buf
  vim.api.nvim_buf_attach(self.bufnr, false, {
    on_bytes = function(_, _, _,
                        start_row, start_col, start_offset,
                        old_end_row, old_end_col, old_offset,
                        new_end_row, new_end_col, new_offset)
      self:_autocmd_update_bytes(_, _, _, start_row, start_col, start_offset,
        old_end_row, old_end_col, old_offset,
        new_end_row, new_end_col, new_offset)
    end,
  })
  -- create autocmds
  vim.api.nvim_create_autocmd({ "VimLeave", "BufLeave" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = function()
      self:free()
    end
  })
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    callback = function()
      vim.schedule(function()
        terminfo.refresh_terminal()
        self.processor:set_cell_sizes()
        self:_free_equations()
        self:_loop()
      end)
    end
  })
  vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = function()
      self:_loop()
    end
  })
  if config.anticonceal then
    vim.api.nvim_create_autocmd({ "CursorMoved" }, {
      buffer = self.bufnr,
      group = augroup,
      callback = function()
        self:normal_display(self.marks)
      end
    })
  end
  vim.api.nvim_create_autocmd({ "ModeChanged" }, {
    buffer = self.bufnr,
    group = augroup,
    callback = function()
      self:_autocmd_update_mode()
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
  self:_free_equations()
  self.processor:free()
  self.timer:stop()
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
  self.equations[event.hash]:set_processor_result(event)
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

function Buffer:_free_equations()
  for _, equation in pairs(self.equations) do
    equation:free()
  end
end

function Buffer:_parse_line_range()
  local first_row, last_row = utils.window.get_line_range()
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
  for equation_hash, locations in pairs(new_locations) do
    for _, loc in ipairs(locations) do
      local mark = self.equations[equation_hash]:create_new_mark({
        start_row = loc.start_row,
        start_col = loc.start_col,
        end_row = loc.end_row,
        end_col = loc.end_col,
      })
      if mark then
        self.marks[mark:get_hash()] = mark
      end
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

function Buffer:_autocmd_update_mode()
  local old_mode = vim.v.event.old_mode:sub(1, 1)
  local mode = vim.v.event.new_mode:sub(1, 1)
  if old_mode == mode then
    return
  end
  if mode == "i" or mode == "R" then
    self.mode = BUFFER_MODE.INSERT
  elseif mode == "n" then
    self.mode = BUFFER_MODE.NORMAL
  end
end

return Buffer
