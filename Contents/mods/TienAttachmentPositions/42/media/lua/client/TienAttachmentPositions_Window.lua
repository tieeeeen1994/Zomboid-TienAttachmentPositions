require "ISUI/ISCollapsableWindow"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "TienAttachmentPositions_Core"

local Core = TienAttachmentPositions

TienAttachmentPositionsWindow = ISCollapsableWindow:derive("TienAttachmentPositionsWindow")
local Window = TienAttachmentPositionsWindow

local FONT = UIFont.Small

local ROWS = {
    { key = "ox", text = "IGUI_TienAttachmentPositions_MoveX", min = -Core.MOVE, max = Core.MOVE, step = 0.005, fmt = "%.3f" },
    { key = "oy", text = "IGUI_TienAttachmentPositions_MoveY", min = -Core.MOVE, max = Core.MOVE, step = 0.005, fmt = "%.3f" },
    { key = "oz", text = "IGUI_TienAttachmentPositions_MoveZ", min = -Core.MOVE, max = Core.MOVE, step = 0.005, fmt = "%.3f" },
    { key = "rx", text = "IGUI_TienAttachmentPositions_TurnX", min = -Core.TURN, max = Core.TURN, step = 1, fmt = "%.0f" },
    { key = "ry", text = "IGUI_TienAttachmentPositions_TurnY", min = -Core.TURN, max = Core.TURN, step = 1, fmt = "%.0f" },
    { key = "rz", text = "IGUI_TienAttachmentPositions_TurnZ", min = -Core.TURN, max = Core.TURN, step = 1, fmt = "%.0f" },
    { key = "s", text = "IGUI_TienAttachmentPositions_Size", min = Core.SIZE_MIN, max = Core.SIZE_MAX, step = 0.01, fmt = "%.2f" },
}

local function measure(text)
    return getTextManager():MeasureStringX(FONT, text)
end

local function wrap(text, width)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and measure(try) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function layout(heading)
    local fh = getTextManager():getFontHeight(FONT)
    local L = { fh = fh }
    L.pad = math.max(8, math.floor(fh * 0.6))
    L.gap = math.max(4, math.floor(fh * 0.3))
    L.rowH = math.max(fh + 4, 18)
    L.labelW = 0
    for _, row in ipairs(ROWS) do
        L.labelW = math.max(L.labelW, measure(getText(row.text)))
    end
    L.valueW = measure("-180.000")
    L.sliderW = math.max(200, fh * 12)
    L.buttons = {
        { text = getText("IGUI_TienAttachmentPositions_Reset"), fn = Window.onReset },
        { text = getText("IGUI_TienAttachmentPositions_ResetAll"), fn = Window.onResetAll },
        { text = getText("IGUI_TienAttachmentPositions_Close"), fn = Window.close },
    }
    L.buttonH = fh + L.gap * 2
    for _, b in ipairs(L.buttons) do
        b.w = measure(b.text) + L.pad * 2
    end
    local maxInner = getCore():getScreenWidth() - 20 - L.pad * 2
    local fixed = L.labelW + L.pad + L.pad + L.valueW
    L.sliderW = math.max(100, math.min(L.sliderW, maxInner - fixed))
    L.innerW = fixed + L.sliderW
    L.buttonRows = { {} }
    local rowW = 0
    for _, b in ipairs(L.buttons) do
        local row = L.buttonRows[#L.buttonRows]
        if #row > 0 and rowW + L.gap + b.w > L.innerW then
            row = {}
            table.insert(L.buttonRows, row)
            rowW = 0
        end
        b.w = math.min(b.w, L.innerW)
        rowW = rowW + (#row > 0 and L.gap or 0) + b.w
        table.insert(row, b)
    end
    L.heading = wrap(heading, L.innerW)
    L.note = wrap(getText("IGUI_TienAttachmentPositions_Note"), L.innerW)
    L.width = L.innerW + L.pad * 2
    return L
end

function Window:new(player, points, heading)
    local L = layout(heading)
    local o = ISCollapsableWindow.new(self, 0, 0, L.width, 100)
    o.L = L
    o.player = player
    o.points = points
    o.point = points[1]
    o.title = getText("IGUI_TienAttachmentPositions_Title")
    o.resizable = false
    local th = o:titleBarHeight()
    L.top = th + L.pad
    local function height()
        return L.top + #L.heading * L.fh + L.gap + #L.note * L.fh + L.pad
            + #ROWS * (L.rowH + L.gap) + L.pad + #L.buttonRows * (L.buttonH + L.gap) - L.gap + L.pad
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if height() > sh then L.note = {} end
    local h = height()
    o:setHeight(h)
    o:setX(math.max(0, math.floor((sw - L.width) / 2)))
    o:setY(math.max(0, math.floor((sh - h) / 3)))
    return o
end

function Window:addText(x, y, text, r, g, b)
    local label = ISLabel:new(x, y, self.L.fh, text, r, g, b, 1, FONT, true)
    label:initialise()
    self:addChild(label)
    return label
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local L = self.L
    local x, y = L.pad, L.top
    for _, line in ipairs(L.heading) do
        self:addText(x, y, line, 1, 1, 1)
        y = y + L.fh
    end
    y = y + L.gap
    for _, line in ipairs(L.note) do
        self:addText(x, y, line, 0.75, 0.75, 0.75)
        y = y + L.fh
    end
    y = y + L.pad
    self.rows = {}
    for _, row in ipairs(ROWS) do
        local textY = y + math.floor((L.rowH - L.fh) / 2)
        self:addText(x, textY, getText(row.text), 0.9, 0.9, 0.7)
        local slider = ISSliderPanel:new(x + L.labelW + L.pad, y, L.sliderW, L.rowH, self, Window.onSlider)
        slider:initialise()
        slider:instantiate()
        slider:setValues(row.min, row.max, row.step, row.step * 10, true)
        slider.key = row.key
        self:addChild(slider)
        local value = self:addText(x + L.labelW + L.pad + L.sliderW + L.pad, textY, "", 0.85, 0.9, 1)
        self.rows[row.key] = { slider = slider, value = value, fmt = row.fmt }
        y = y + L.rowH + L.gap
    end
    y = y + L.pad - L.gap
    for _, row in ipairs(L.buttonRows) do
        local bx = L.pad
        for _, b in ipairs(row) do
            local button = ISButton:new(bx, y, b.w, L.buttonH, b.text, self, b.fn)
            button:initialise()
            button:instantiate()
            self:addChild(button)
            bx = bx + b.w + L.gap
        end
        y = y + L.buttonH + L.gap
    end
    self:reload()
end

function Window:current()
    local ns = Core.IdOf(self.player)
    local v = Core.ValuesFor(ns, self.point)
    local c = Core.Identity()
    if v then
        for _, key in ipairs(Core.FIELDS) do c[key] = v[key] or c[key] end
    end
    return c
end

function Window:show(v)
    self.v = v
    for key, row in pairs(self.rows) do
        row.slider:setCurrentValue(v[key], true)
        row.value:setName(string.format(row.fmt, row.slider:getCurrentValue()))
    end
end

function Window:reload()
    if self.rows then self:show(self:current()) end
end

function Window:onSlider(value, slider)
    local row = self.rows[slider.key]
    if not row then return end
    self.v[slider.key] = value
    row.value:setName(string.format(row.fmt, value))
    Core.Client.Edit(self.player, self.points, self.v)
end

function Window:onReset()
    self:show(Core.Identity())
    Core.Client.Edit(self.player, self.points, self.v)
end

function Window:onResetAll()
    self:show(Core.Identity())
    Core.Client.ResetAll(self.player)
end

function Window:close()
    Core.Client.Flush()
    if Core.Client.window == self then Core.Client.window = nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end
