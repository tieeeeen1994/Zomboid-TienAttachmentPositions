-- Stand-ins for the vanilla UI classes the window uses, then the window file. Args: mod dir, font height.
local modDir, fontH = ...
UIFont = { Small = "Small" }
local charW = fontH * 0.5
getTextManager = function()
    return { MeasureStringX = function(_, _, t) return #t * charW end, getFontHeight = function() return fontH end }
end
getCore = function() return { getScreenWidth = function() return SCREEN_W or 1920 end, getScreenHeight = function() return SCREEN_H or 1080 end } end

local function element(x, y, w, h)
    return { x = x, y = y, width = w, height = h, children = {} }
end
local Base = {}
Base.__index = Base
function Base:initialise() end
function Base:instantiate() end
function Base:addChild(c) table.insert(self.children, c) c.parent = self end
function Base:setHeight(h) self.height = h end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:addToUIManager() self.shown = true end
function Base:removeFromUIManager() self.shown = false end
function Base:getRight() return self.x + self.width end
function Base:getBottom() return self.y + self.height end
function Base:getX() return self.x end
function Base:getWidth() return self.width end
function Base:setVisible(v) self.visible = v end
function Base:setAlwaysOnTop(v) self.onTop = v end
function Base:bringToTop() self.top = true end

ISCollapsableWindow = setmetatable({}, { __index = Base })
ISCollapsableWindow.__index = ISCollapsableWindow
function ISCollapsableWindow:derive(name) local c = setmetatable({ Type = name }, { __index = self }) c.__index = c return c end
function ISCollapsableWindow.new(self, x, y, w, h) local o = element(x, y, w, h) o.titleFontHgt = fontH return setmetatable(o, self) end
function ISCollapsableWindow:titleBarHeight() return math.max(16, self.titleFontHgt + 1) end
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:close() self.visible = false end

ISLabel = setmetatable({}, { __index = Base })
ISLabel.__index = ISLabel
function ISLabel:new(x, y, h, name) local o = element(x, y, #name * charW, h) o.name = name return setmetatable(o, self) end
function ISLabel:setName(n) self.name = n self.width = #n * charW end

ISButton = setmetatable({}, { __index = Base })
ISButton.__index = ISButton
function ISButton:new(x, y, w, h, title, target, fn) local o = element(x, y, w, h) o.title, o.target, o.fn, o.enabled = title, target, fn, true return setmetatable(o, self) end
function ISButton:setEnable(v) self.enabled = v end
function ISButton:enableAcceptColor() self.accept = true end
function ISButton:enableCancelColor() self.cancel = true end
function ISButton:click() if self.enabled then self.fn(self.target, self) end end

ISPanel = setmetatable({}, { __index = Base })
ISPanel.__index = ISPanel
function ISPanel:derive(name) local c = setmetatable({ Type = name }, { __index = self }) c.__index = c return c end
function ISPanel.new(self, x, y, w, h) local o = element(x, y, w, h) return setmetatable(o, self) end
function ISPanel:createChildren() end
function ISPanel:addToUIManager() self.shown = true if not self.created then self.created = true self:createChildren() end M.dialog = self end

ISSliderPanel = setmetatable({}, { __index = Base })
ISSliderPanel.__index = ISSliderPanel
function ISSliderPanel:new(x, y, w, h, target, fn) local o = element(x, y, w, h) o.target, o.onValueChange, o.currentValue = target, fn, 0 return setmetatable(o, self) end
function ISSliderPanel:setValues(a, b, s) self.minValue, self.maxValue, self.stepValue = a, b, s end
function ISSliderPanel:setCurrentValue(v, ignore)
    v = math.floor(v / self.stepValue + 0.5) * self.stepValue
    if v < self.minValue then v = self.minValue elseif v > self.maxValue then v = self.maxValue end
    self.currentValue = v
    if not ignore then self.onValueChange(self.target, v, self) end
end
function ISSliderPanel:getCurrentValue() return self.currentValue end

local f = assert(loadfile(modDir .. "/media/lua/client/TienAttachmentPositions_Window.lua"))
f()
