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
  
  self:set_size(self.width, self.height)
  return true
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
  
  -- Draw center line
  g:set_color(200, 200, 200)
  g:draw_line(0, self.height/2, self.width, self.height/2, 1)
  
  -- Ensure view parameters are valid
  self.viewSize = math.max(1, math.min(self.viewSize, length))
  self.startIndex = math.max(0, math.min(self.startIndex, length - self.viewSize))
  
  -- Find min/max values in view range
  local minVal, maxVal = math.huge, -math.huge
  for i = self.startIndex, math.min(self.startIndex + self.viewSize - 1, length - 1) do
    local val = array:get(i)
    if val then
      minVal = math.min(minVal, val)
      maxVal = math.max(maxVal, val)
    end
  end
  
  if minVal == maxVal then
    minVal = minVal - 0.5
    maxVal = maxVal + 0.5
  end
  
  -- Scale factor for y values
  local scale = (self.height/2 - 2) / math.max(math.abs(minVal), math.abs(maxVal))
  
  -- Draw waveform
  g:set_color(0, 0, 0)
  
  -- Sample step size (samples per pixel)
  local step = self.viewSize / self.width
  
  -- Start path with first point
  local firstVal = array:get(self.startIndex)
  local firstY = self.height/2 - (firstVal * scale)
  local p = Path(0, firstY)
  
  -- Add line segments connecting each sample
  local lastX = 0
  local lastY = firstY
  
  for i = 1, self.width do
    local index = math.floor(self.startIndex + (i-1) * step)
    if index < length then
      local val = array:get(index)
      if val then
        local x = i-1
        local y = self.height/2 - (val * scale)
        p:line_to(x, y)
        lastX = x
        lastY = y
      end
    end
  end
  
  g:stroke_path(p, 1)
  
  -- Draw info text
  g:set_color(100, 100, 100)
  g:draw_text(string.format("Range: %.2f to %.2f", minVal, maxVal), 5, 5, 190, 10)
  g:draw_text(string.format("View: %d-%d/%d (%.1f sp/px)", 
    self.startIndex, math.min(self.startIndex + self.viewSize, length), 
    length, self.viewSize/self.width), 5, self.height - 15, 190, 10)
end

function explore:mouse_down(x, y)
  -- Just store start position and view state
  self.dragStartX = x
  self.dragStartY = y
  self.dragStartViewSize = self.viewSize
  self.dragStartIndex = self.startIndex
  self.dragStartSample = math.floor(self.startIndex + (x / self.width) * self.viewSize)
end

function explore:mouse_drag(x, y)
  local array = pd.Table:new():sync(self.arrayName)
  if not array then return end
  local length = array:length()

  -- Calculate zoom factor based on vertical drag
  local dy = (y - self.dragStartY) * 0.01
  local zoomFactor = math.exp(dy)
  local newViewSize = math.max(self.width, math.min(length,
    math.floor(self.dragStartViewSize * zoomFactor)))
  
  -- Calculate the pixel offset where the original sample should now be
  local dx = x - self.dragStartX
  -- Use current view size for samples-per-pixel calculation
  local samplesPerPixel = newViewSize / self.width
  local sampleOffset = dx * samplesPerPixel
  
  -- Calculate new start index that maintains the clicked point under the mouse
  local newStart = self.dragStartSample - sampleOffset - (newViewSize / 2)
  
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
