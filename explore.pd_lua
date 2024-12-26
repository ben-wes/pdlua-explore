local explore = pd.Class:new():register("explore")

function explore:initialize(sel, atoms)
  self.inlets = 1
  self.outlets = 1
  
  -- Store array name from creation argument
  if type(atoms[1]) == "string" then
    self.arrayName = atoms[1]
    -- Try to get initial array length
    local array = pd.Table:new():sync(self.arrayName)
    if array then
      self.arrayLength = array:length()
    else
      self:error("explore: array " .. self.arrayName .. " not found")
      return false
    end
  else
    self:error("explore: expected array name as argument")
    return false
  end
  
  -- View parameters
  self.width = 200
  self.height = 140
  self.startIndex = 0  -- Start of visible window
  self.viewSize = self.arrayLength  -- Initially show full array
  
  -- Add hover tracking
  self.hoverX = nil
  self.hoverY = nil
  
  self:set_size(self.width, self.height)

  -- Add frame clock
  self.frameClock = pd.Clock:new():register(self, "frame")
  self.frameRate = 20  -- 20 fps
  self.frameClock:delay(1000 / self.frameRate)  -- Convert to milliseconds
  
  self:set_size(self.width, self.height)
  return true
end

function explore:frame()
  self:repaint()
  -- Schedule next frame
  self.frameClock:delay(1000 / self.frameRate)
end

-- Add cleanup to stop the clock when the object is destroyed
function explore:destroy()
  if self.frameClock then
    self.frameClock:destruct()
  end
end

function explore:mouse_move(x, y)
  self.hoverX = x
  self.hoverY = y
  self:repaint()
end

function explore:paint(g)
  -- Get array data
  local array = pd.Table:new():sync(self.arrayName)
  if not array then return end
  
  local length = array:length()
  if length == 0 then return end
  self.arrayLength = length
  
  -- Draw background
  g:set_color(240, 240, 240)
  g:fill_all()
  
  -- Ensure view parameters are valid
  self.viewSize = math.max(1, math.min(self.viewSize, length))
  self.startIndex = math.max(0, math.min(self.startIndex, length - self.viewSize))
  
  local samplesPerPixel = self.viewSize / self.width
  
  -- Find min/max values in view range using same sampling as drawing
  local minVal, maxVal = math.huge, -math.huge
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
        local text = string.format("Sample: %d Value: %.3f", sampleIndex, value)
        g:draw_text(text, 5, self.height - 30, 190, 10)
      end
    end
  end
  
  -- Draw info text
  g:set_color(100, 100, 100)
  g:draw_text(string.format("Range: %.2f to %.2f", minVal, maxVal), 5, 5, 190, 10)
  g:draw_text(string.format("View: %d-%d/%d (%.1f sp/px)", 
    self.startIndex, math.min(self.startIndex + self.viewSize, length), 
    length, self.viewSize/self.width), 5, self.height - 15, 190, 10)
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
  local array = pd.Table:new():sync(self.arrayName)
  if not array then return end
  local length = array:length()

  -- Calculate initial samples per pixel
  local currentSamplesPerPixel = self.dragStartViewSize / self.width

  -- Calculate zoom factor based on vertical drag
  local dy = (y - self.dragStartY) * 0.01
  local zoomFactor = math.exp(dy)
  
  -- Calculate target samples per pixel
  local targetSamplesPerPixel = currentSamplesPerPixel * zoomFactor
  
  -- Handle 1:1 zoom boundary
  if targetSamplesPerPixel < 1 then
    if currentSamplesPerPixel > 1 then
      -- If coming from zoomed out, clamp to 1:1
      targetSamplesPerPixel = 1
    end
    -- Otherwise allow zooming past 1:1
  end
  
  local newViewSize = math.max(1, math.min(length,
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
  
  self:repaint()
end

function explore:in_1_symbol(name)
  if type(name) == "string" then
    self.arrayName = name
    -- Reset view to show full array
    local array = pd.Table:new():sync(self.arrayName)
    if array then
      self.arrayLength = array:length()
      self.startIndex = 0
      self.viewSize = self.arrayLength
      self:repaint()
    end
  end
end
