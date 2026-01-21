local Processor = {}
Processor.__index = Processor

local config = require("mdmath.config").opts
local terminfo =  require("mdmath.terminfo")
local PLUGIN_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local PROCESSOR_DIR = PLUGIN_DIR .. "/mdmath-js"
local PROCESSOR_JS = PROCESSOR_DIR .. "/src/processor.js"

function Processor.new(buffer)
  local self = {}
  setmetatable(self, Processor)

  self.stdin = vim.uv.new_pipe()
  self.stdout = vim.uv.new_pipe()
  self.stderr = vim.uv.new_pipe()
  self.buffer = buffer
  assert(self.stdin, "[MDMATH] Failed to open stdin for processor")
  assert(self.stdout, "[MDMATH] Failed to open stdout for processor")
  assert(self.stderr, "[MDMATH] Failed to open stderr for processor")

  self.handle = vim.uv.spawn("node", {
    args = { PROCESSOR_JS },
    stdio = { self.stdin, self.stdout, self.stderr }
  })

  self.stdout:read_start(function(_, data)
    self:_resend_data(data)
  end)

  self.stderr:read_start(function(_, data)
    print(data)
  end)

  self:set_cell_sizes()
  self:set_configs()
  return self
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
  self:_send_json({
    type = "setpixel",
    wpix = pixels_per_cell_w,
    hpix = pixels_per_cell_h,
    inline_method = "example",
    display_method = "example",
  })
end

function Processor:set_configs()
  self:_send_json({
    type = "config",
    blratio = config.bottom_line_ratio,
    ppad = config.pixel_padding,
  })
end

function Processor:_send_json(value)
  local b64_json = vim.base64.encode(vim.fn.json_encode(value))
  local len = #b64_json
  self.stdin:write( string.format("%d:%s", len, b64_json))
end

function Processor:request_image(req)
  self.stdin:write(
    string.format("request:%d:%s:%d:%d:%s:%d:%d:%d:%s:",
    #req.hash, req.hash, req.inline, req.flags,
    req.color, req.ncells_w, req.ncells_h, #req.equation, req.equation)
  )
end

function Processor:_resend_data(data)
  local iter = data:gmatch("([a-zA-Z0-9-/.]*):([a-zA-Z0-9-/.]*):([a-zA-Z0-9- \\/.]*):")
  for code, hash, value in iter do
    if code == "image" then
      self.buffer:notify_processor({
        event_type = "image",
        hash = hash,
        path = value
      })
    elseif code == "error" then
      self.buffer:notify_processor({
        event_type = "error",
        hash = hash,
        error = value
      })
    end
  end
end

return Processor
