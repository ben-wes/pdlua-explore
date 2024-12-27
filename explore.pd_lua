local explore = pd.Class:new():register("explore")

function explore:initialize(sel, atoms)
  self.inlets = 1
  self.outlets = 1
  
  -- View parameters
  self.width = 200
  self.height = 140
  
  -- Parse creation arguments
  for i, arg in ipairs(atoms) do
    if arg == "-width" then
      self.width = math.max(math.floor(atoms[i+1] or 200), 96)
    elseif arg == "-height" then
      self.height = math.max(math.floor(atoms[i+1] or 140), 140)
    elseif type(arg) == "string" then
      self.arrayName = arg
    end
  end
  
  -- Initialize view parameters with safe defaults
  self.arrayLength = 1  -- Safe default
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
  self.frameRate = 20  -- fps
  self.frameClock:delay(1000 / self.frameRate)
  self.arrayMissing = false
  
  self.manualScale = nil  -- nil means auto-scale
  
  self.needsRepaint = false
  
  self:set_size(self.width, self.height)
  return true
end

function explore:frame()
  if self.needsRepaint then
    self:repaint()
    self.needsRepaint = false
  end
  self.frameClock:delay(1000 / self.frameRate)
end

function explore:destroy()
  if self.frameClock then
    self.frameClock:destruct()
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
  self.width = math.max(math.floor(x[1] or 200), 96)
  self:set_args(self:get_creation_args())
  self:set_size(self.width, self.height)
  self.needsRepaint = true
end

function explore:in_1_height(x)
  self.height = math.max(math.floor(x[1] or 140), 140)
  self:set_args(self:get_creation_args())
  self:set_size(self.width, self.height)
  self.needsRepaint = true
end

function explore:get_creation_args()
  local args = {self.arrayName}
  table.insert(args, "-width")
  table.insert(args, self.width)
  table.insert(args, "-height")
  table.insert(args, self.height)
  return args
end

function explore:frame()
  self:repaint()
  -- Schedule next frame
  self.frameClock:delay(1000 / self.frameRate)
end

-- stop the clock when the object is destroyed
function explore:destroy()
  if self.frameClock then
    self.frameClock:destruct()
  end
end

function explore:mouse_move(x, y)
  self.hoverX = x
  self.hoverY = y
  self.needsRepaint = true
end

function explore:paint(g)
  -- Draw background
  g:set_color(240, 240, 240)
  g:fill_all()
  
  -- Get array data
  local array = self:get_array()
  if not array then return end
  local length = self.arrayLength  -- Use the cached length
  
  -- Ensure view parameters are valid
  self.viewSize = math.max(1, math.min(self.viewSize, self.arrayLength))
  self.startIndex = math.max(0, math.min(self.startIndex, self.arrayLength - self.viewSize))
  
  local samplesPerPixel = self.viewSize / self.width
    local minVal, maxVal = math.huge, -math.huge

  -- Only calculate min/max if we're using auto-scale
  if not self.manualScale then
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
      minVal = minVal - 0.5
      maxVal = maxVal + 0.5
    end
  else
    -- Use manual scale
    minVal = -self.manualScale
    maxVal = self.manualScale
  end
  
  -- Scale factor for y values
  local scale = (self.height/2 - 2) / math.max(math.abs(minVal), math.abs(maxVal))
  
  -- Draw center line - always visible since we center around 0
  g:set_color(200, 200, 200)
  local zeroY = self.height/2
  g:draw_line(0, zeroY, self.width, zeroY, 1)

  -- Draw hover highlight line behind waveform if needed
  if samplesPerPixel <= 1 and self.hoverX and self.hoverX >= 0 and self.hoverX < self.width then
    local sampleOffset = math.floor(((self.hoverX - 1) * self.width / (self.width - 2)) * samplesPerPixel)
    -- Calculate x position same way as for the sample highlight
    local x = 2 + (sampleOffset / samplesPerPixel) * (self.width - 2) / self.width
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
    
    -- Adjust the range to ensure we include the rightmost sample
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

  -- Also adjust hover detection to match the drawing mode
  if samplesPerPixel <= 1 and self.hoverX and self.hoverX >= 1 and self.hoverX < self.width-1 then
    -- Convert pixel position back to sample offset, accounting for the border in zoomed mode
    local sampleOffset = math.floor(((self.hoverX - 1) * self.width / (self.width - 2)) * samplesPerPixel)
    local sampleIndex = self.startIndex + sampleOffset
    
    if sampleIndex < length then
      local value = array:get(sampleIndex)
      if value then
        -- Convert exact sample position back to pixels
        local x = 1 + (sampleOffset / samplesPerPixel) * (self.width - 2) / self.width
        local y = self.height/2 - (value * scale)
        
        g:set_color(0, 80, 160)
        g:stroke_rect(x-1, y-1, 3, 3, 1)
        
        -- Draw sample info text
        g:set_color(0, 0, 0)
        local text = string.format("Index: %d Value: %.3f", sampleIndex, value)
        g:draw_text(text, 5, self.height - 30, 190, 10)
      end
    end
  end
  
  -- Draw info text
  g:set_color(100, 100, 100)
  g:draw_text(string.format("%.2f", maxVal), 5, 5, 190, 10)
  local samplesPerPixel = self.viewSize / self.width
  local format = samplesPerPixel < 1 and "%.2f" or "%.0f"
  g:draw_text(string.format("%d..%d (" .. format .. " sp/px)", 
    self.startIndex, math.min(self.startIndex + self.viewSize, length), 
    samplesPerPixel), 5, self.height - 15, 190, 10)

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
  local array = pd.table(self.arrayName)
  if not array then return end
  local length = array:length()

  -- Calculate initial samples per pixel
  local currentSamplesPerPixel = self.dragStartViewSize / self.width

  -- Calculate zoom factor based on vertical drag
  local dy = (y - self.dragStartY) * 0.01
  local zoomFactor = math.exp(dy)
  
  -- Calculate target samples per pixel
  local targetSamplesPerPixel = currentSamplesPerPixel * zoomFactor
  
  -- Ensure minimum 3 samples in view
  local minViewSize = 2
  local newViewSize = math.max(minViewSize, math.min(length,
    math.floor(self.width * targetSamplesPerPixel)))

  -- Calculate the pixel offset where the original sample should now be
  local dx = x - self.dragStartX
  -- Calculate new start index keeping the same view fraction under mouse
  local currentFraction = (x / self.width)
  local sampleAtMouse = self.dragStartIndex + (self.dragStartFraction * self.dragStartViewSize)
  local newStart = sampleAtMouse - (currentFraction * newViewSize)
  
  -- Update view parameters ensuring bounds
  self.viewSize = newViewSize
  self.startIndex = math.max(0, math.min(length - self.viewSize,
    math.floor(newStart)))
  
  self.needsRepaint = true
end

function explore:in_1_symbol(name)
  if type(name) == "string" then
    self.arrayName = name
    -- Reset view to show full array
    local array = pd.table(self.arrayName)
    if array then
      self.arrayLength = array:length()
      self.startIndex = 0
      self.viewSize = self.arrayLength
      self.needsRepaint = true
    end
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
  local hue_start, hue_end = table.unpack(self.colors.graphGradients.hue)
  local sat_start, sat_end = table.unpack(self.colors.graphGradients.saturation)
  local bright_start, bright_end = table.unpack(self.colors.graphGradients.brightness)

  for i = 1, count do
    local hue = hue_start + (hue_end - hue_start) * ((i - 1) / math.max(1, count - 1))
    local saturation = sat_start + (sat_end - sat_start) * ((i - 1) / math.max(1, count - 1))
    local brightness = bright_start + (bright_end - bright_start) * ((i - 1) / math.max(1, count - 1))
    local r, g, b = self:hsv_to_rgb(hue, saturation, brightness)
    table.insert(colors, {r, g, b})
  end

  return colors
end

function explore:get_array()
  -- Helper function to get array and length safely
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