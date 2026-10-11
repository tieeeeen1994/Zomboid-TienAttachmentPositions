require "TienAttachmentPositions_Core"

local Core = TienAttachmentPositions
local Client = {}
Core.Client = Client

Client.seq = 0
Client.localSeq = {}
Client.pending = {}
Client.SEND_MS = 150

local lastSend = 0

local function isLocalUser(user)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and player:getUsername() == user then return true end
    end
    return false
end

local function refresh(user)
    local newBody = false
    Core.EachPlayer(function(player)
        if Core.NoteBody(player) then newBody = true end
    end)
    if newBody then Core.ReapplyAll() end
    Core.EachPlayer(function(player)
        if player:isLocalPlayer() then Core.Normalize(player) end
        if newBody or user == nil or player:getUsername() == user then player:resetModelNextFrame() end
    end)
end

function Client.Handle(command, args)
    args = args or {}
    if command == "all" then
        Core.ids = args.ids or {}
        Core.reg = args.reg or {}
        Core.pts = args.pts or {}
        Core.RegisterAll()
        refresh(nil)
        if Client.window then Client.window:reload() end
    elseif command == "pt" then
        local user, ns, point = args.u, args.n, args.p
        if type(user) ~= "string" or type(ns) ~= "string" or type(point) ~= "string" then return end
        Core.ids[user] = ns
        Core.reg[ns] = Core.reg[ns] or {}
        Core.reg[ns][point] = true
        local key = user .. "|" .. point
        local stale = args.seq and Client.localSeq[key] and args.seq < Client.localSeq[key]
        if not stale then
            Core.pts[ns] = Core.pts[ns] or {}
            Core.pts[ns][point] = args.v
        end
        Core.Register(ns, point)
        refresh(user)
        if not stale and Client.window and Client.window.point == point and isLocalUser(user) then
            Client.window:reload()
        end
    elseif command == "resend" then
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then Core.Resend(player) end
        end
    end
end

function Client.Edit(player, point, v)
    local user = player:getUsername()
    Client.seq = Client.seq + 1
    Client.localSeq[user .. "|" .. point] = Client.seq
    local ns = Core.IdOf(player)
    if ns and Core.IsRegistered(ns, point) then
        Core.pts[ns] = Core.pts[ns] or {}
        Core.pts[ns][point] = Core.Clean(v)
        Core.ApplyValues(ns, point)
        Core.Normalize(player)
        player:resetModelNextFrame()
    end
    Client.pending[user .. "|" .. point] = { player = player, point = point, v = v, seq = Client.seq }
end

function Client.Flush()
    local pending = Client.pending
    Client.pending = {}
    for _, p in pairs(pending) do
        Core.ToServer(p.player, "set", { p = p.point, v = p.v, seq = p.seq })
    end
    lastSend = getTimestampMs()
end

function Client.ResetAll(player)
    Client.pending = {}
    Core.ToServer(player, "resetAll", {})
end

local function onTick()
    for _ in pairs(Client.pending) do
        if getTimestampMs() - lastSend >= Client.SEND_MS then Client.Flush() end
        return
    end
end

local function quietPlysken()
    local par = PAR_AttachCalibrate
    if not par then return end
    if par.onContextMenu then Events.OnFillInventoryObjectContextMenu.Remove(par.onContextMenu) end
    if not par.TienAttachmentPositions then
        par.TienAttachmentPositions = true
        par.applyAll = function() end
    end
    if par.window and par.window.close then pcall(function() par.window:close() end) end
    if par.restoreFactory then pcall(par.restoreFactory) end
end

local function firstItem(items)
    local entry = items and items[1]
    if not entry then return nil end
    if type(entry) == "table" then
        return entry.items and entry.items[1] or entry.item
    end
    return entry
end

local function slotName(item, base)
    local slotType = item.getAttachedSlotType and item:getAttachedSlotType()
    local name = slotType and getTextOrNull("IGUI_HotbarAttachment_" .. slotType)
    return name or base
end

local function onContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local item = firstItem(items)
    if not player or not instanceof(item, "InventoryItem") then return end
    local attached = player:getAttachedItems()
    local loc = attached and attached:getLocation(item)
    if not loc then return end
    local base = Core.BaseOf(loc)
    local point = Core.PointOf(base)
    if not point then return end
    if Core.NoteBody(player) then Core.ReapplyAll() end
    local option = context:addOption(getText("IGUI_TienAttachmentPositions_Menu"), player, Client.Open, item, base, point)
    local reason
    if not Core.Adjustable(point) then
        reason = getText("IGUI_TienAttachmentPositions_Clothing")
    elseif not Core.HasBodyPoint(point) then
        reason = getText("IGUI_TienAttachmentPositions_NoPoint")
    end
    if reason then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = reason
        option.toolTip = tooltip
    end
end

function Client.Open(player, item, base, point)
    if Client.window then Client.window:close() end
    local window = TienAttachmentPositionsWindow:new(player, point, item:getDisplayName() .. " - " .. slotName(item, base))
    window:initialise()
    window:addToUIManager()
    Client.window = window
end

local function onGameStart()
    quietPlysken()
    Core.ResetWorld()
    local player = getSpecificPlayer(0)
    if player then Core.ToServer(player, "hello", {}) end
end

quietPlysken()
Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Core.MODULE then return end
    Client.Handle(command, args)
end)
