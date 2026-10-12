require "TienAttachmentPositions_Core"

local Core = TienAttachmentPositions
local Client = {}
Core.Client = Client

Client.seq = 0
Client.localSeq = {}
Client.pending = {}
Client.SEND_MS = 150
Client.CHECK_MS = 2000

local lastSend = 0
local lastCheck = 0
local helloAt, helloTries = nil, 0
local helloWait = false
Client.HELLO_MS = 1000
Client.HELLO_TRIES = 20

local function sayHello()
    local player = getSpecificPlayer(0)
    if not player then return end
    helloTries = helloTries + 1
    helloAt = getTimestampMs()
    print("[TienAttachmentPositions] " .. Core.VERSION .. " asking the server for positions (request " .. helloTries .. ")")
    Core.ToServer(player, "hello", { v = Core.VERSION })
end

local function tryHello()
    local player = getSpecificPlayer(0)
    if not player or (isClient() and player:getOnlineID() < 0) then return end
    helloWait = false
    sayHello()
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

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
        helloAt = nil
        helloWait = false
        Core.ids = args.ids or {}
        Core.reg = args.reg or {}
        Core.pts = args.pts or {}
        local me = getSpecificPlayer(0)
        local mine = me and Core.IdOf(me)
        print("[TienAttachmentPositions] positions from the server: " .. count(Core.ids) .. " players, yours: "
            .. (mine and count(Core.pts[mine]) or 0) .. " spots")
        Core.RegisterAll()
        refresh(nil)
        if Client.window then Client.window:serverUpdate() end
    elseif command == "pt" then
        local user, ns = args.u, args.n
        if type(user) ~= "string" or type(ns) ~= "string" then return end
        local points = type(args.ps) == "table" and args.ps or { args.p }
        Core.ids[user] = ns
        Core.reg[ns] = Core.reg[ns] or {}
        local reload = false
        for _, point in pairs(points) do
            if type(point) == "string" then
                Core.reg[ns][point] = true
                local key = user .. "|" .. point
                local stale = args.seq and Client.localSeq[key] and args.seq < Client.localSeq[key]
                if not stale then
                    Core.pts[ns] = Core.pts[ns] or {}
                    Core.pts[ns][point] = args.v
                    if Client.window and Client.window.has[point] then reload = true end
                end
                Core.Register(ns, point)
            end
        end
        refresh(user)
        if reload and isLocalUser(user) then Client.window:serverUpdate() end
    elseif command == "resend" then
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player then Core.Resend(player) end
        end
    end
end

function Client.Edit(player, points, v)
    if type(points) == "string" then points = { points } end
    local user = player:getUsername()
    Client.seq = Client.seq + 1
    local ns = Core.IdOf(player)
    local changed = false
    for _, point in ipairs(points) do
        Client.localSeq[user .. "|" .. point] = Client.seq
        if ns and Core.IsRegistered(ns, point) then
            Core.pts[ns] = Core.pts[ns] or {}
            Core.pts[ns][point] = Core.Clean(v)
            Core.ApplyValues(ns, point)
            changed = true
        end
    end
    if changed then
        Core.Normalize(player)
        player:resetModelNextFrame()
    end
    local copy = {}
    for _, key in ipairs(Core.FIELDS) do copy[key] = v[key] end
    Client.pending[user .. "|" .. table.concat(points, "|")] = { player = player, points = points, v = copy, seq = Client.seq }
end

function Client.Flush()
    local pending = Client.pending
    Client.pending = {}
    for _, p in pairs(pending) do
        Core.ToServer(p.player, "set", { ps = p.points, v = p.v, seq = p.seq })
    end
    lastSend = getTimestampMs()
end

local function slotLocations(slotType)
    local list = {}
    local defs = ISHotbarAttachDefinition
    if type(slotType) ~= "string" or type(defs) ~= "table" then return list end
    local def
    for _, d in ipairs(defs) do
        if type(d) == "table" and d.type == slotType then def = d break end
    end
    if not def or type(def.attachments) ~= "table" then return list end
    for _, loc in pairs(def.attachments) do
        if type(loc) == "string" then list[#list + 1] = loc end
    end
    for _, r in ipairs(type(defs.replacements) == "table" and defs.replacements or {}) do
        if type(r) == "table" and r.name == def.name and type(r.replacement) == "table" then
            for key, loc in pairs(r.replacement) do
                if def.attachments[key] ~= nil and type(loc) == "string" and loc ~= "null" then
                    list[#list + 1] = loc
                end
            end
        end
    end
    return list
end

local function usable(p)
    return p ~= nil and Core.Adjustable(p) and Core.HasBodyPoint(p)
end

local staticGroups = {}

local function slotGroup(slotType)
    local static = staticGroups[slotType]
    if not static then
        static = {}
        for _, loc in ipairs(slotLocations(slotType)) do
            local p = Core.PointOf(loc)
            if usable(p) then static[p] = true end
        end
        staticGroups[slotType] = static
    end
    local points = {}
    for p in pairs(static) do points[p] = true end
    return points
end

function Client.ResetGroups()
    staticGroups = {}
end

function Client.SlotPoints(item, point)
    local points = { point }
    local slotType = item and item.getAttachedSlotType and item:getAttachedSlotType()
    local others = {}
    for p in pairs(slotGroup(slotType)) do
        if p ~= point then others[#others + 1] = p end
    end
    table.sort(others)
    for _, p in ipairs(others) do points[#points + 1] = p end
    return points
end

function Client.Prepare(player, points)
    local ns = Core.IdOf(player)
    local fresh = {}
    for _, point in ipairs(points) do
        if not (ns and Core.IsRegistered(ns, point)) then fresh[#fresh + 1] = point end
    end
    if #fresh == 0 then return true end
    Client.Edit(player, fresh, Core.Identity())
    Client.Flush()
    return false
end

function Client.Preview(player, points, v)
    local ns = Core.IdOf(player)
    if not ns then return end
    for _, point in ipairs(points) do
        if Core.IsRegistered(ns, point) then Core.ApplyValues(ns, point, v) end
    end
    player:resetModelNextFrame()
end

function Client.ResetAll(player)
    Client.pending = {}
    Core.ToServer(player, "resetAll", {})
end

local function onTick()
    local now = getTimestampMs()
    if helloWait then tryHello() end
    if helloAt and now - helloAt >= Client.HELLO_MS then
        if helloTries < Client.HELLO_TRIES then
            sayHello()
        else
            helloAt = nil
            print("[TienAttachmentPositions] the server never sent the positions (" .. helloTries .. " requests)")
        end
    end
    if now - lastCheck >= Client.CHECK_MS then
        lastCheck = now
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player and Core.IdOf(player) then Core.Normalize(player) end
        end
    end
    for _ in pairs(Client.pending) do
        if now - lastSend >= Client.SEND_MS then Client.Flush() end
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
    if Client.window then
        local old = Client.window
        old:close(function() Client.Open(player, item, base, point) end)
        if Client.window == old and old.bringToTop then old:bringToTop() end
        return
    end
    local window = TienAttachmentPositionsWindow:new(player, Client.SlotPoints(item, point),
        item:getDisplayName() .. " - " .. slotName(item, base))
    window:initialise()
    window:addToUIManager()
    Client.window = window
end

local function onGameStart()
    quietPlysken()
    Core.ResetWorld()
    Client.ResetGroups()
    helloTries = 0
    helloAt = nil
    helloWait = true
    tryHello()
end

quietPlysken()
Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Core.MODULE then return end
    Client.Handle(command, args)
end)
