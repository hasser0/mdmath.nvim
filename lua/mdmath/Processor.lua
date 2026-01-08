Processor = {}

local config = require("mdmath.config").opts
local terminfo =  require("mdmath.terminfo")
local PLUGIN_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local PROCESSOR_DIR = PLUGIN_DIR .. "/mdmath-js"
local PROCESSOR_JS = PROCESSOR_DIR .. "/src/processor.js"

function Processor:new(callback)
  local processor = {}
  setmetatable(processor, { __index = self })

  processor.stdin = vim.uv.new_pipe()
  assert(processor.stdin, "failed to open stdin for processor: ")
  processor.stdout = vim.uv.new_pipe()
  assert(processor.stdout, "failed to open stdin for processor: ")
  processor.stderr = vim.uv.new_pipe()
  assert(processor.stderr, "failed to open stdin for processor: ")

  processor.handle = vim.uv.spawn("node", {
    args = { PROCESSOR_JS },
    stdio = { processor.stdin, processor.stdout, processor.stderr }
  }, function(_, _) end)

  processor.stdout:read_start(function(_, data)
    callback(data)
  end)

  processor.stderr:read_start(function(_, data)
    callback(data)
  end)

  processor:set_cell_sizes()
  processor:_set_float_var("blratio", config.bottom_line_ratio)
  processor:_set_int_var("ppad", config.pixel_padding)

  return processor
end

function Processor:free()
  self.stdin:close()
  self.stdout:close()
  self.stderr:close()
  self.handle:close()
  self.handle = nil
end

function Processor:set_cell_sizes()
  local pixels_per_cell_w, pixels_per_cell_h = terminfo.get_pixels_per_cell()
  self:_set_float_var("wpix", pixels_per_cell_w)
  self:_set_float_var("hpix", pixels_per_cell_h)
end

function Processor:request_image(req)
  self.stdin:write(
    string.format("request:%d:%s:%d:%d:%s:%d:%d:%d:%s:",
    #req.hash, req.hash, req.inline, req.flags,
    req.color, req.ncells_w, req.ncells_h, #req.equation, req.equation)
  )
end

function Processor:_set_float_var(var, value)
  self.stdin:write(string.format("setfloat:%s:%.2f:", var, value))
end

function Processor:_set_int_var(var, value)
  self.stdin:write(string.format("setint:%s:%d:", var, value))
end

return Processor
