local Window = {}
Window.__index = Window

local Equation = require("mdmath.equation")
local Processor = require("mdmath.processor")
local window_strategies = require("mdmath.window_strategies")
local config = require("mdmath.config").opts
local utils = require("mdmath.utils")
local terminfo = require("mdmath.terminfo")
local augroup = vim.api.nvim_create_augroup("MdmathManager", { clear = true })
local windows = {}

local WINDOW_MODE = {
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

function Window.enable_mdmath_for_window()
  vim.schedule(function()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == nil then
      return
    end
    local filetype = vim.filetype.match({ filename = bufname })
    local found = false
    for _, ft in ipairs(config.filetypes) do
      if ft == filetype then
        found = true
        break
      end
    end
    if not found then
      return
    end
    windows[winid] = Window.new(winid, bufnr, filetype)
  end)
end

function Window.disable_mdmath_for_window()
  local winid = vim.api.nvim_get_current_win()
  windows[winid]:free()
  windows[winid] = nil
end

function Window.clear_mdmath_for_window()
  local winid = vim.api.nvim_get_current_win()
  windows[winid]:free_equations()
end

function Window.attach_buffer_to_window(bufnr, winid)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == nil then
      return
    end
  local filetype = vim.filetype.match({ filename = bufname })
  windows[winid] = Window.new(winid, bufnr, filetype)
end

function Window.detach_buffer_from_window(bufnr, winid)
  windows[winid]:free()
  windows[winid] = nil
end

function Window.new(winid, bufnr, filetype)
  local self = {}

  setmetatable(self, Window)
  self.insert_display = window_strategies[config.insert_strategy]
  self.normal_display = window_strategies[config.normal_strategy]

  self.bufnr = bufnr
  self.winid = winid
  self.filetype = filetype
  self.mode = WINDOW_MODE.NORMAL
  self.equations = {}
  self.marks = {}
  self.parser = _get_parser(bufnr, filetype)
  self.tty = vim.uv.new_tty(1, false)
  self.active = true

  self.processor = Processor.new(self)

  -- create autocmds
  vim.api.nvim_create_autocmd({ "WinClosed", "VimLeave" }, {
    pattern = tostring(winid),
    group = augroup,
    callback = function(args)
      require("mdmath.window").disable_mdmath_for_window()
    end
  })
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    callback = _debounce(function(args)
      terminfo.refresh_terminal()
      self.processor:set_terminal_sizes()
      self:free_equations()
      self:_loop()
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter" }, {
    group = augroup,
    callback = _debounce(function(args)
      self:_loop()
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    group = augroup,
    callback = _debounce(function(args)
      self:normal_display(self.marks)
    end, config.update_interval)
  })
  vim.api.nvim_create_autocmd({ "ModeChanged" }, {
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

function Window:free()
  if not self.active then
    return
  end
  self.active = false
  self:free_equations()
  self.processor:free()
  windows[self.winid] = nil

  --TODO REMOVE AUTOCMDS
  vim.api.nvim_clear_autocmds({
    group = augroup,
  })
end

function Window:get_bufnr()
  return self.bufnr
end

function Window:get_tty()
  return self.tty
end

function Window:notify_processor(event)
  if event.hash then
    self.equations[event.hash]:set_processor_result(event)
  end
end

function Window:remove_mark(mark)
  self.marks[mark:get_hash()] = nil
end

function Window:remove_equation(equation)
  self.equations[equation:get_hash()] = nil
end

function Window:_loop()
  self:_parse_line_range()
  self:_draw()
end

function Window:_draw()
  if self.mode == WINDOW_MODE.NORMAL then
    self:normal_display(self.marks)
  elseif self.mode == WINDOW_MODE.INSERT then
    self:insert_display(self.marks)
  end
end

function Window:free_equations()
  for _, equation in pairs(self.equations) do
    equation:free()
  end
end

function Window:get_line_range()
  local info = vim.fn.getwininfo(self.winid)[1]
  local top = info.topline
  local bottom = info.botline
  return top, bottom
end

function Window:get_cursor()
  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  return cursor[1] - 1, cursor[2]
end

function Window:_parse_line_range()
  local first_row, last_row = self:get_line_range()
  self.parser:parse({ first_row, last_row })

  local parser = nil
  local query = nil
  if self.filetype == "markdown" then
    parser = self.parser
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
          window = self,
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

function Window:_autocmd_update_bytes(_, _, _,
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

function Window:_autocmd_update_mode(old_mode, mode)
  if mode == "i" or mode == "R" then
    self.mode = WINDOW_MODE.INSERT
  elseif mode == "n" then
    self.mode = WINDOW_MODE.NORMAL
  end
end

return Window
