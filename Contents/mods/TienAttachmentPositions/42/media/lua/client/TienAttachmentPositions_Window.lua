require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "TienAttachmentPositions_Core"

local Core = TienAttachmentPositions

TienAttachmentPositionsWindow = ISCollapsableWindow:derive("TienAttachmentPositionsWindow")
local Window = TienAttachmentPositionsWindow

TienAttachmentPositionsAsk = ISPanel:derive("TienAttachmentPositionsAsk")
local Ask = TienAttachmentPositionsAsk

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

local function copy(v)
    local c = {}
    for _, key in ipairs(Core.FIELDS) do c[key] = v[key] end
    return c
end

local function same(a, b)
    for _, key in ipairs(Core.FIELDS) do
        if math.abs((a[key] or 0) - (b[key] or 0)) > 0.0005 then return false end
    end
    return true
end

local function metrics()
    local fh = getTextManager():getFontHeight(FONT)
    local M = { fh = fh }
    M.pad = math.max(8, math.floor(fh * 0.6))
    M.gap = math.max(4, math.floor(fh * 0.3))
    M.buttonH = fh + M.gap * 2
    return M
end

local function buttonSpecs(list, M)
    local w = 0
    for i, b in ipairs(list) do
        b.text = getText(b.key)
        b.tip = b.tipKey and getText(b.tipKey) or nil
        b.w = measure(b.text) + M.pad * 2
        w = w + b.w + (i > 1 and M.gap or 0)
    end
    return w
end

local function layout(heading)
    local L = metrics()
    L.rowH = math.max(L.fh + 4, 18)
    L.labelW = 0
    for _, row in ipairs(ROWS) do
        L.labelW = math.max(L.labelW, measure(getText(row.text)))
    end
    L.valueW = measure("-180.000")
    L.left = {
        { key = "IGUI_TienAttachmentPositions_Reset", tipKey = "IGUI_TienAttachmentPositions_ResetTip", fn = Window.onReset, id = "reset" },
        { key = "IGUI_TienAttachmentPositions_Restore", tipKey = "IGUI_TienAttachmentPositions_RestoreTip", fn = Window.onRestore, id = "restore" },
    }
    L.right = {
        { key = "IGUI_TienAttachmentPositions_Save", fn = Window.onSave, id = "save", accept = true },
        { key = "IGUI_TienAttachmentPositions_Close", fn = Window.onClose, id = "close" },
    }
    L.leftW = buttonSpecs(L.left, L)
    L.rightW = buttonSpecs(L.right, L)
    L.resetAll = { key = "IGUI_TienAttachmentPositions_ResetAll", tipKey = "IGUI_TienAttachmentPositions_ResetAllTip", fn = Window.onResetAll, id = "resetAll" }
    buttonSpecs({ L.resetAll }, L)
    L.th = math.max(16, L.fh + 1)
    L.title = getText("IGUI_TienAttachmentPositions_Title")
    local titleSide = L.resetAll.w + (L.th - 2) + L.gap * 3
    local maxInner = getCore():getScreenWidth() - 20 - L.pad * 2
    local fixed = L.labelW + L.pad + L.pad + L.valueW
    local want = math.max(fixed + math.max(200, L.fh * 12), L.leftW + L.pad * 2 + L.rightW,
        measure(L.title) + titleSide * 2 - L.pad * 2)
    L.sliderW = math.max(100, math.min(want, maxInner) - fixed)
    L.innerW = fixed + L.sliderW
    L.bottomRows = (L.leftW + L.pad + L.rightW <= L.innerW) and 1 or 2
    for _, b in ipairs(L.left) do b.w = math.min(b.w, L.innerW) end
    for _, b in ipairs(L.right) do b.w = math.min(b.w, L.innerW) end
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
    o.has = {}
    for _, p in ipairs(points) do o.has[p] = true end
    o.title = L.title
    o.resizable = false
    o.buttons = {}
    local th = o:titleBarHeight()
    L.top = th + L.pad
    local function height()
        return L.top + #L.heading * L.fh + L.gap + #L.note * L.fh + L.pad
            + #ROWS * (L.rowH + L.gap) + L.pad + L.bottomRows * (L.buttonH + L.gap) - L.gap + L.pad
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

function Window:addButton(spec, x, y, h)
    local button = ISButton:new(x, y, spec.w, h, spec.text, self, spec.fn)
    button:initialise()
    button:instantiate()
    if spec.tip then button.tooltip = spec.tip end
    if spec.accept then button:enableAcceptColor() end
    self:addChild(button)
    self.buttons[spec.id] = button
    return button
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local L = self.L
    local th = self:titleBarHeight()
    local edge = self.collapseButton and self.collapseButton:getX() or (self.width - 1 - (th - 2))
    self:addButton(L.resetAll, edge - L.gap - L.resetAll.w, 1, th - 2)
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
    local bx = L.pad
    for _, b in ipairs(L.left) do
        self:addButton(b, bx, y, L.buttonH)
        bx = bx + b.w + L.gap
    end
    if L.bottomRows > 1 then y = y + L.buttonH + L.gap end
    bx = L.pad + L.innerW - L.rightW
    for _, b in ipairs(L.right) do
        self:addButton(b, math.max(L.pad, bx), y, L.buttonH)
        bx = bx + b.w + L.gap
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

function Window:isDirty()
    return self.v ~= nil and self.saved ~= nil and not same(self.v, self.saved)
end

function Window:updateButtons()
    local dirty = self:isDirty()
    local b = self.buttons
    if b.save then b.save:setEnable(dirty) end
    if b.restore then b.restore:setEnable(dirty) end
    if b.reset then b.reset:setEnable(self.v ~= nil and not same(self.v, Core.Identity())) end
end

function Window:show(v)
    self.v = v
    for key, row in pairs(self.rows) do
        row.slider:setCurrentValue(v[key], true)
        row.value:setName(string.format(row.fmt, row.slider:getCurrentValue()))
    end
    self:updateButtons()
end

function Window:reload()
    if not self.rows then return end
    self.saved = self:current()
    self:show(copy(self.saved))
end

function Window:preview()
    Core.Client.Prepare(self.player, self.points)
    Core.Client.Preview(self.player, self.points, self.v)
    self:updateButtons()
end

function Window:serverUpdate()
    if not self.rows then return end
    if self:isDirty() then
        self.saved = self:current()
        Core.Client.Preview(self.player, self.points, self.v)
        self:updateButtons()
    else
        self:reload()
    end
end

function Window:onSlider(value, slider)
    local row = self.rows[slider.key]
    if not row then return end
    self.v[slider.key] = value
    row.value:setName(string.format(row.fmt, value))
    self:preview()
end








function Window:onSave()
    Core.Client.Edit(self.player, self.points, self.v)
    Core.Client.Flush()
    self.saved = copy(self.v)
    self:updateButtons()
end

function Window:onReset()
    self:show(Core.Identity())
    self:preview()
end

function Window:onRestore()
    self:show(copy(self.saved or self:current()))
    Core.Client.Preview(self.player, self.points, nil)
    self:updateButtons()
end

function Window:ask(textKey, buttons)
    if self.asking then self.asking:dismiss() end
    local dialog = Ask:new(self, getText(textKey), buttons)
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setAlwaysOnTop(true)
    self.asking = dialog
    return dialog
end

function Window:onResetAll()
    self:ask("IGUI_TienAttachmentPositions_ResetAllAsk", {
        { id = "reset", key = "IGUI_TienAttachmentPositions_ResetAllYes", danger = true, fn = Window.doResetAll },
        { id = "cancel", key = "IGUI_TienAttachmentPositions_Cancel" },
    })
end

function Window:doResetAll()
    Core.Client.ResetAll(self.player)
    self.saved = Core.Identity()
    self:show(Core.Identity())
    Core.Client.Preview(self.player, self.points, self.v)
end

function Window:onClose()
    self:close()
end

function Window:close(after)
    if type(after) ~= "function" then after = nil end
    if not self:isDirty() then
        self:closeNow()
        if after then after() end
        return
    end
    self:ask("IGUI_TienAttachmentPositions_CloseAsk", {
        { id = "save", key = "IGUI_TienAttachmentPositions_Save", accept = true, fn = function(w)
            w:onSave()
            w:closeNow()
            if after then after() end
        end },
        { id = "discard", key = "IGUI_TienAttachmentPositions_Discard", danger = true, fn = function(w)
            w:closeNow()
            if after then after() end
        end },
        { id = "cancel", key = "IGUI_TienAttachmentPositions_Cancel" },
    })
end

function Window:closeNow()
    if self.asking then self.asking:dismiss() end
    if self:isDirty() then
        self.v = copy(self.saved)
        Core.Client.Preview(self.player, self.points, nil)
    end
    if Core.Client.window == self then Core.Client.window = nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

function Ask:new(owner, text, buttons)
    local M = metrics()
    local rowW = buttonSpecs(buttons, M)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local textW = math.max(1, math.min(math.max(rowW, M.fh * 20), sw - 20 - M.pad * 2))
    local lines = wrap(text, textW)
    local w = math.max(textW, rowW) + M.pad * 2
    local h = M.pad + #lines * M.fh + M.pad + M.buttonH + M.pad
    local x = owner.x + math.floor((owner.width - w) / 2)
    local y = owner.y + math.floor((owner.height - h) / 2)
    x = math.max(0, math.min(x, sw - w))
    y = math.max(0, math.min(y, sh - h))
    local o = ISPanel.new(self, x, y, w, h)
    o.M = M
    o.owner = owner
    o.lines = lines
    o.specs = buttons
    o.rowW = rowW
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
    o.moveWithMouse = true
    return o
end

function Ask:createChildren()
    local M = self.M
    local y = M.pad
    for _, line in ipairs(self.lines) do
        local label = ISLabel:new(M.pad, y, M.fh, line, 1, 1, 1, 1, FONT, true)
        label:initialise()
        self:addChild(label)
        y = y + M.fh
    end
    y = y + M.pad
    local x = self.width - M.pad - self.rowW
    self.buttons = {}
    for _, spec in ipairs(self.specs) do
        local button = ISButton:new(x, y, spec.w, M.buttonH, spec.text, self, Ask.onButton)
        button.internal = spec.id
        button:initialise()
        button:instantiate()
        if spec.accept then button:enableAcceptColor() end
        if spec.danger then button:enableCancelColor() end
        self:addChild(button)
        self.buttons[spec.id] = button
        x = x + spec.w + M.gap
    end
end

function Ask:onButton(button)
    self:press(button.internal)
end

function Ask:press(id)
    self:dismiss()
    for _, spec in ipairs(self.specs) do
        if spec.id == id and spec.fn then spec.fn(self.owner) end
    end
end

function Ask:dismiss()
    if self.owner.asking == self then self.owner.asking = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end
