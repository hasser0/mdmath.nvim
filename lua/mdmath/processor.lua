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
    type = "pixel",
    cellWidthInPixels = pixels_per_cell_w,
    cellHeightInPixels = pixels_per_cell_h,
  })
end

function Processor:set_configs()
  -- TODO add methods for display
  self:_send_json({
    type = "config",
    bottomLineRatio = config.bottom_line_ratio,
    pixelPadding = config.pixel_padding,
    centerInline = config.center_inline,
    centerDisplay = config.center_display,
    foreground = config.foreground,
    displayMethod = "overlay_show",
    inlineMethod = config.inline_strategy_show,
  })
end

function Processor:request_image(req)
  req.type = "image"
  self:_send_json(req)
end

function Processor:_send_json(value)
  local b64_json = vim.base64.encode(vim.fn.json_encode(value))
  local len = #b64_json
  self.stdin:write(string.format("%d:%s:", len, b64_json))
end

function Processor:_resend_data(data)
  local i = 1
  local length = #data
  while i <= length do
    local start_pos, end_pos, str_len = data:find("^(%d+):", i)
    if not start_pos then
      break
    end
    str_len = tonumber(str_len)
    local content_start = end_pos + 1
    local content_end = end_pos + str_len
    local segment = data:sub(content_start, content_end)
    vim.schedule(function()
      local json = vim.fn.json_decode(vim.base64.decode(segment))
      self.buffer:notify_processor(json)
    end)
    i = content_end + 2
  end
end

return Processor
