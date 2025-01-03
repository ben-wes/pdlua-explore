local explore = pd.Class:new():register("explore")

function explore:initialize(sel, atoms)
  self.inlets = 1
  self.outlets = 1
  
  -- View parameters
  self.arrayNameUnexpanded = nil
  
  -- Parse creation arguments
  self.width, self.height, self.arrayName = parse_args(atoms)
  
  -- Initialize view parameters with safe defaults
  self.arrayLength = 1
  self.startIndex = 0
  self.viewSize = 1
  
  -- Initialize markers array and color configuration
  self.markers = {}
  self.colors = {
    graphGradients = {
      hue =        {210, 340},
      saturation = { 90,  94},
      brightness = { 70,  80},
    }
  }
  
  -- frame clock
  self.frameClock = pd.Clock:new():register(self, "frame")
  self.argsClock = pd.Clock:new():register(self, "args")
  self.frameRate = 20  -- fps
  self.frameClock:delay(1000 / self.frameRate)
  self.argsClock:delay(0)
  self.arrayMissing = false
  
  self.manualScale = nil  -- nil means auto-scale
  
  self.needsRepaint = false
  
  self:set_size(self.width, self.height)
  return true
end

function parse_args(atoms)
  local width, height, arrayName = nil, nil, nil
  for i, arg in ipairs(atoms) do
    if arg == "-width" then
      width = math.max(math.floor(atoms[i+1] or 200), 96)
    elseif arg == "-height" then
      height = math.max(math.floor(atoms[i+1] or 140), 140)
    elseif type(arg) == "string" then
      arrayName = arg
    end
  end
  return width or 200, height or 140, arrayName
end

function explore:args()
  local args = self:get_args()
  self.width, self.height, self.arrayNameUnexpanded = parse_args(args)  -- Parse creation arguments
end

function explore:frame()
  if self.needsRepaint then
    self:repaint()
    self.needsRepaint = false
  else
    -- Only repaint if array content has changed
    local array = self:get_array()
    if array then
      -- Check if array content has changed since last frame
      local currentContent = self:get_array_hash()
      if currentContent ~= self.lastArrayHash then
        self:repaint()
        self.lastArrayHash = currentContent
      end
    end
  end
  self.frameClock:delay(1000 / self.frameRate)
end

function explore:destroy()
  if self.frameClock then
    self.frameClock:destruct()
  end
  if self.argsClock then
    self.argsClock:destruct()
  end
end

function explore:in_1_float(f)
  -- Handle single float as a special case
  self.markers = {}
  local colors = self:generate_colors(1)
  
  table.insert(self.markers, {
    index = f or 0,
    color = colors[1]
  })
  
  self.needsRepaint = true
end

function explore:in_1_list(atoms)
  -- Clear existing markers
  self.markers = {}
  
  -- Generate colors for all markers using our palette
  local colors = self:generate_colors(#atoms)
  
  -- Create a marker for each input value with corresponding color
  for i, value in ipairs(atoms) do
    table.insert(self.markers, {
      index = value or 0,
      color = colors[i]
    })
  end
  
  self.needsRepaint = true
end

function explore:in_1_width(x)
  self.width = math.max(math.floor(x[1] or 200), 24)
  self:set_args(self:get_creation_args())
  self:set_size(self.width, self.height)
  self.needsRepaint = true
end

function explore:in_1_height(x)
  self.height = math.max(math.floor(x[1] or 140), 24)
  self:set_args(self:get_creation_args())
  self:set_size(self.width, self.height)
  self.needsRepaint = true
end

function explore:get_creation_args()
  local args = {self.arrayNameUnexpanded or self.arrayName}
  table.insert(args, "-width")
  table.insert(args, self.width)
  table.insert(args, "-height")
  table.insert(args, self.height)
  return args
end

function explore:mouse_move(x, y)
  self.hoverX = x
  self.hoverY = y
  self.needsRepaint = true
end

function explore:paint(g)
  -- Cache frequently accessed values
  local width, height = self.width, self.height
  local halfHeight = height / 2
  local array = self:get_array()
  if not array then return end
  local length = self.arrayLength
  local startIndex = self.startIndex
  local viewSize = self.viewSize
  local samplesPerPixel = viewSize / width
  local manualScale = self.manualScale
  
  -- Draw background
  g:set_color(248, 248, 248)
  g:fill_all()
  
  -- Ensure view parameters are valid
  viewSize = math.max(1, math.min(viewSize, length))
  startIndex = math.max(0, math.min(startIndex, length - viewSize))
  
  local minVal, maxVal = math.huge, -math.huge

  -- Only calculate min/max if we're using auto-scale
  if not manualScale then
    -- Find min/max values in view range using same sampling as drawing
    if samplesPerPixel <= 1 then
      -- When zoomed in, look at actual samples including the rightmost one
      local visibleSamples = math.min(self.viewSize + 1, length - self.startIndex)
      for i = self.startIndex, self.startIndex + visibleSamples - 1 do
        local val = array:get(i)
        if val then
          minVal = math.min(minVal, val)
          maxVal = math.max(maxVal, val)
        end
      end
    else
      -- When zoomed out, sample at pixel intervals
      local step = self.viewSize / self.width
      for i = 0, self.width - 1 do
        local index = math.floor(self.startIndex + i * step)
        if index < length then
          local val = array:get(index)
          if val then
            minVal = math.min(minVal, val)
            maxVal = math.max(maxVal, val)
          end
        end
      end
    end

    if minVal == maxVal then
      minVal = minVal - 0.1
      maxVal = maxVal + 0.1
    end
  else
    -- Use manual scale
    minVal = -manualScale
    maxVal = manualScale
  end
  
  -- Scale factor for y values
  local scale = (self.height/2 - 2) / math.max(math.abs(minVal), math.abs(maxVal))
  
  -- Draw center line
  g:set_color(230, 230, 230)
  local zeroY = self.height/2
  g:draw_line(0, zeroY, self.width, zeroY, 1)

  -- Draw hover highlight line behind waveform
  if samplesPerPixel <= 1 and self.hoverX and self.hoverX >= 0 and self.hoverX < self.width-1 then
    -- Convert pixel position to sample position, accounting for border
    local normalizedX = (self.hoverX - 1) * self.width / (self.width - 2)
    -- Calculate the fractional sample position
    local exactSampleOffset = normalizedX * samplesPerPixel
    -- Round to nearest sample instead of floor
    local sampleOffset = math.floor(exactSampleOffset + 0.5)
    -- Calculate x position same way as for the sample highlight
    local x = 1 + (sampleOffset / samplesPerPixel) * (self.width - 2) / self.width
    g:set_color(200, 200, 200)
    g:draw_line(x, 0, x, self.height, 1)
  end  

  -- Draw waveform
  g:set_color(0, 0, 0)
  
  if samplesPerPixel <= 1 then
    -- Zoomed in mode - direct lines between samples
    -- First draw connecting lines in bright color
    g:set_color(150, 150, 150)
    
    local firstVal = array:get(self.startIndex)
    local firstY = self.height/2 - (firstVal * scale)
    local p = Path(1, firstY)  -- Start at x=1
    local visibleSamples = math.min(self.viewSize + 1, length - self.startIndex)
    
    -- Iterate over actual samples
    for i = 0, visibleSamples - 1 do
      local val = array:get(self.startIndex + i)
      if val then
        -- Convert sample index to pixel position, scaled to width-2 pixels
        local x = 1 + (i / samplesPerPixel) * (self.width - 2) / self.width
        local y = self.height/2 - (val * scale)
        p:line_to(x, y)
      end
    end
    g:stroke_path(p, 1)
    
    -- Then draw sample points in black
    g:set_color(0, 0, 0)
    for i = 0, visibleSamples - 1 do
      local val = array:get(self.startIndex + i)
      if val then
        local x = 1 + (i / samplesPerPixel) * (self.width - 2) / self.width
        local y = self.height/2 - (val * scale)
        g:fill_rect(x, y, 2, 2)
      end
    end
  else
    -- Zoomed out mode - use full width
    local step = self.viewSize / self.width
    local firstVal = array:get(self.startIndex)
    local firstY = self.height/2 - (firstVal * scale)
    local p = Path(0, firstY)  -- Start at x=0
    
    for i = 1, self.width - 1 do
      local index = math.floor(self.startIndex + i * step)
      if index < length then
        local val = array:get(index)
        if val then
          local x = i
          local y = self.height/2 - (val * scale)
          p:line_to(x, y)
        end
      end
    end
    g:stroke_path(p, 1)
  end

  -- Draw hover rectangle and text
  if samplesPerPixel <= 1 and self.hoverX and self.hoverX >= 0 and self.hoverX < self.width-1 then
    -- Use exactly the same calculations as the vertical line
    local normalizedX = (self.hoverX - 1) * self.width / (self.width - 2)
    local exactSampleOffset = normalizedX * samplesPerPixel
    local sampleOffset = math.floor(exactSampleOffset + 0.5)
    local sampleIndex = self.startIndex + sampleOffset
    
    if sampleIndex < length then
      local value = array:get(sampleIndex)
      if value then
        -- Use exactly the same x position calculation as the vertical line
        local x = 1 + (sampleOffset / samplesPerPixel) * (self.width - 2) / self.width
        local y = self.height/2 - (value * scale)
        
        g:set_color(0, 90, 200)
        g:stroke_rect(x-1, y-1, 3, 3, 1)
        
        -- Draw sample info text
        g:set_color(0, 0, 0)
        local text = string.format("sample %d: %.4f", sampleIndex, value)
        g:draw_text(text, 3, 15, 190, 10)
      end
    end
  end
  
  -- Draw info text
  g:set_color(1)
  -- Draw array name in upper left
  g:draw_text(self.arrayNameUnexpanded or "no array", 3, 3, 190, 10)
  -- Draw scale value in upper right
  g:draw_text(string.format("% 8.2f", maxVal or 0), self.width-50, 3, 50, 10)
  -- Draw samples info at bottom
  local samplesPerPixel = self.viewSize / self.width
  local formatSamplesPerPixel = samplesPerPixel < 1 and "%.2f" or "%.0f"
  g:draw_text(string.format("1px = ".. samplesPerPixel .. "sp", 
    samplesPerPixel), 3, self.height - 13, 190, 10)
  -- Calculate number of digits needed based on array length
  local numDigits = math.floor(math.log(length, 10)) + 1
  local indexText = string.format("%d..%d", 
    self.startIndex, math.min(self.startIndex + self.viewSize, length))
  local paddedText = string.format("%20s", indexText)
  
  g:draw_text(paddedText,
    self.width - 122, self.height - 13, 120, 10)

  -- Draw markers
  for _, marker in ipairs(self.markers) do
    -- Set the color for this marker
    g:set_color(table.unpack(marker.color))
    
    -- Calculate marker position based on zoom level
    local x
    if samplesPerPixel <= 1 then
      -- Zoomed in mode - use adjusted x position
      local markerOffset = marker.index - self.startIndex
      x = 1 + (markerOffset / samplesPerPixel) * (self.width - 2) / self.width
    else
      -- Zoomed out mode - direct pixel mapping
      local step = self.viewSize / self.width
      x = (marker.index - self.startIndex) / step
    end
    
    -- Only draw if marker is in view
    if x >= 0 and x <= self.width then
      -- Draw marker line
      g:draw_line(x, 0, x, self.height, 1)
    end
  end
end

function explore:mouse_down(x, y)
  -- Store start position and view state
  self.dragStartX = x
  self.dragStartY = y
  self.dragStartViewSize = self.viewSize
  self.dragStartIndex = self.startIndex
  -- Also store where in the view we clicked (as a fraction)
  self.dragStartFraction = x / self.width
end

function explore:mouse_drag(x, y)
  local array = self:get_array()
  if not array then return end
  local length = self.arrayLength
  local width = self.width

  -- Calculate initial samples per pixel
  local currentSamplesPerPixel = self.dragStartViewSize / width
  
  -- Calculate zoom factor based on vertical drag
  local dy = (y - self.dragStartY) * 0.01
  local zoomFactor = math.exp(dy)
  
  -- Calculate target samples per pixel
  local targetSamplesPerPixel = currentSamplesPerPixel * zoomFactor
  
  -- Check if we're crossing the 1:1 boundary
  if (currentSamplesPerPixel > 1 and targetSamplesPerPixel < 1) or
     (currentSamplesPerPixel < 1 and targetSamplesPerPixel > 1) then
    -- Stop at 1:1 unless we started exactly at 1:1
    if math.abs(currentSamplesPerPixel - 1) > 0.001 then
      targetSamplesPerPixel = 1
    end
  end
  
  -- Ensure minimum 2 samples in view
  local minViewSize = 2
  local newViewSize = math.max(minViewSize, math.min(length,
    math.floor(width * targetSamplesPerPixel)))

  -- Calculate new start index keeping the same view fraction under mouse
  local currentFraction = (x / width)
  local sampleAtMouse = self.dragStartIndex + (self.dragStartFraction * self.dragStartViewSize)
  local newStart = sampleAtMouse - (currentFraction * newViewSize)
  
  -- Update view parameters ensuring bounds
  self.viewSize = newViewSize
  self.startIndex = math.max(0, math.min(length - newViewSize,
    math.floor(newStart)))
  
  self.needsRepaint = true
end

function explore:in_1_symbol(name)
  if type(name) == "string" then
    self.arrayNameUnexpanded = name
    self.arrayName = self:canvas_realizedollar(name)
    local array = self:get_array()
    if array then self.needsRepaint = true end
  end
end

function explore:hsv_to_rgb(h, s, v)
  h = h % 360  -- Ensure h is in the range 0-359
  s = s / 100  -- Convert s to 0-1 range
  v = v / 100  -- Convert v to 0-1 range

  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c

  local r, g, b
  if h < 60 then
    r, g, b = c, x, 0
  elseif h < 120 then
    r, g, b = x, c, 0
  elseif h < 180 then
    r, g, b = 0, c, x
  elseif h < 240 then
    r, g, b = 0, x, c
  elseif h < 300 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end

  return math.floor((r + m) * 255 + 0.5), 
         math.floor((g + m) * 255 + 0.5), 
         math.floor((b + m) * 255 + 0.5)
end

function explore:generate_colors(count)
  local colors = {}
  local gradients = self.colors.graphGradients
  local hue_start, hue_end = gradients.hue[1], gradients.hue[2]
  local sat_start, sat_end = gradients.saturation[1], gradients.saturation[2]
  local bright_start, bright_end = gradients.brightness[1], gradients.brightness[2]
  local count_minus_1 = math.max(1, count - 1)

  for i = 1, count do
    local t = (i - 1) / count_minus_1
    local hue = hue_start + (hue_end - hue_start) * t
    local saturation = sat_start + (sat_end - sat_start) * t
    local brightness = bright_start + (bright_end - bright_start) * t
    local r, g, b = self:hsv_to_rgb(hue, saturation, brightness)
    colors[i] = {r, g, b}
  end

  return colors
end

function explore:get_array()
  -- Helper function to get array and length safely
  if not self.arrayName then return nil end  -- Return nil if no array name set
  
  local array = pd.table(self.arrayName)
  if array then
    self.arrayLength = array:length()
    -- Update view size if not yet initialized properly
    if self.viewSize == 1 then
      self.viewSize = self.arrayLength
    end
    return array
  end
  return nil
end

function explore:in_1_scale(x)
  if x[1] then
    -- Set manual scale (-f to +f)
    self.manualScale = math.abs(x[1])
  else
    -- Reset to auto-scale
    self.manualScale = nil
  end
  self.needsRepaint = true
end

-- Add this helper function to compute a simple hash of visible array content
function explore:get_array_hash()
  local array = self:get_array()
  if not array then return nil end
  
  -- Only hash visible portion for performance
  local hash = 0
  local step = self.viewSize / self.width
  for i = 0, self.width - 1 do
    local index = math.floor(self.startIndex + i * step)
    if index < self.arrayLength then
      local val = array:get(index)
      if val then
        -- Simple rolling hash
        hash = hash + val
      end
    end
  end
  return hash
end
