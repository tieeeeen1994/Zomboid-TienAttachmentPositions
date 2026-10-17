TienAttachmentPositions = TienAttachmentPositions or {}
local Core = TienAttachmentPositions

Core.MODULE = "TienAttachmentPositions"
Core.VERSION = "0.1.10"
Core.MOVE = 0.5
Core.TURN = 180
Core.SIZE_MIN = 0.25
Core.SIZE_MAX = 3
Core.MAX_POINTS = 300
Core.MAX_SLOT_POINTS = 64
Core.FIELDS = { "ox", "oy", "oz", "rx", "ry", "rz", "s" }

Core.ids = Core.ids or {}
Core.moveLogs = 0
Core.reg = Core.reg or {}
Core.pts = Core.pts or {}
Core.locs = Core.locs or {}

local SKIP = { head_hat = true, bowtie = true }

function Core.Group()
    return AttachedLocations and AttachedLocations.getGroup("Human") or nil
end

function Core.IsClone(loc)
    return type(loc) == "string" and loc:match("@%d+$") ~= nil
end

function Core.BaseOf(loc)
    if type(loc) ~= "string" then return loc end
    return loc:match("^(.-)@%d+$") or loc
end

function Core.CloneName(name, ns)
    return name .. "@" .. ns
end

local pointMap, pointMapSize

local function pointMapFresh()
    local group = Core.Group()
    if not group then return nil end
    local size = group:size()
    if pointMap and pointMapSize == size then return pointMap end
    pointMap = {}
    for i = 0, size - 1 do
        local location = group:getLocationByIndex(i)
        local id = location and location:getId()
        if id and not id:find("@", 1, true) and not SKIP[id] then
            local point = location:getAttachmentName()
            if point and point ~= "" then
                pointMap[point] = pointMap[point] or {}
                table.insert(pointMap[point], id)
            end
        end
    end
    pointMapSize = size
    return pointMap
end

function Core.PointLocations(point)
    local map = pointMapFresh()
    return map and map[point] or nil
end

function Core.PointOf(loc)
    if type(loc) ~= "string" then return nil end
    local base = Core.BaseOf(loc)
    if SKIP[base] then return nil end
    local group = Core.Group()
    local location = group and group:getLocation(base)
    local point = location and location:getAttachmentName()
    if not point or point == "" or point:find("@", 1, true) then return nil end
    return point
end

function Core.Adjustable(point)
    if type(point) ~= "string" or point == "" or point:find("@", 1, true) or point:find(":", 1, true) then
        return false
    end
    local ok, bodyLocation = pcall(function() return ItemBodyLocation.get(ResourceLocation.of(point)) end)
    return not (ok and bodyLocation ~= nil)
end

local function clampRound(x, lo, hi, default)
    x = tonumber(x) or default
    if x ~= x then x = default end
    if x < lo then x = lo elseif x > hi then x = hi end
    return math.floor(x * 1000 + 0.5) / 1000
end

function Core.Clean(v)
    if type(v) ~= "table" then return nil end
    local c = {
        ox = clampRound(v.ox, -Core.MOVE, Core.MOVE, 0),
        oy = clampRound(v.oy, -Core.MOVE, Core.MOVE, 0),
        oz = clampRound(v.oz, -Core.MOVE, Core.MOVE, 0),
        rx = clampRound(v.rx, -Core.TURN, Core.TURN, 0),
        ry = clampRound(v.ry, -Core.TURN, Core.TURN, 0),
        rz = clampRound(v.rz, -Core.TURN, Core.TURN, 0),
        s = clampRound(v.s, Core.SIZE_MIN, Core.SIZE_MAX, 1),
    }
    if c.ox == 0 and c.oy == 0 and c.oz == 0 and c.rx == 0 and c.ry == 0 and c.rz == 0 and c.s == 1 then
        return nil
    end
    return c
end

function Core.Identity()
    return { ox = 0, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 }
end

function Core.IdOf(chr)
    if not chr or not chr.getUsername then return nil end
    local name = chr:getUsername()
    return name and Core.ids[name] or nil
end

function Core.ValuesFor(ns, point)
    local points = ns and Core.pts[ns]
    return points and points[point] or nil
end

function Core.IsRegistered(ns, point)
    local points = ns and Core.locs[ns]
    return points ~= nil and points[point] == true
end

local scriptIndex
local factory = {}

local function buildScriptIndex()
    scriptIndex = {}
    local manager = getScriptManager()
    local all = manager and manager.getAllModelScripts and manager:getAllModelScripts()
    if not all then return end
    for i = 0, all:size() - 1 do
        local script = all:get(i)
        for j = 0, script:getAttachmentCount() - 1 do
            local attachment = script:getAttachment(j)
            local id = attachment and attachment:getId()
            if id and not id:find("@", 1, true) then
                scriptIndex[id] = scriptIndex[id] or {}
                table.insert(scriptIndex[id], script)
            end
        end
    end
end

local function logIndex()
    local scripts, bodyCount, bodyPoints = 0, 0, 0
    local seen = {}
    for _, list in pairs(scriptIndex) do
        for _, script in ipairs(list) do
            if not seen[script] then
                seen[script] = true
                scripts = scripts + 1
                if Core.IsBody(script) then
                    bodyCount = bodyCount + 1
                    bodyPoints = bodyPoints + script:getAttachmentCount()
                end
            end
        end
    end
    print("[TienAttachmentPositions] model scripts with points: " .. scripts .. ", bodies: " .. bodyCount
        .. ", body points: " .. bodyPoints)
end

function Core.ScriptsWith(point)
    if not scriptIndex then
        buildScriptIndex()
        logIndex()
    end
    return scriptIndex[point] or {}
end

local bodies

local function addBody(script)
    if script and not bodies[script] then
        bodies[script] = true
        return true
    end
    return false
end

local function knownBodies()
    if not bodies then
        bodies = {}
        local manager = getScriptManager()
        addBody(manager:getModelScript("FemaleBody"))
        addBody(manager:getModelScript("MaleBody"))
    end
    return bodies
end

function Core.NoteBody(chr)
    knownBodies()
    local visual = chr and chr.getHumanVisual and chr:getHumanVisual()
    return addBody(visual and visual:getModelScript())
end

function Core.IsBody(script)
    return knownBodies()[script] == true
end

function Core.HasBodyPoint(point)
    for _, script in ipairs(Core.ScriptsWith(point)) do
        if Core.IsBody(script) then return true end
    end
    return false
end

local function vec(v)
    if not v then return 0, 0, 0 end
    return v:x(), v:y(), v:z()
end

local function factoryOf(script, point, attachment)
    factory[script] = factory[script] or {}
    local f = factory[script][point]
    if f then return f end
    local ox, oy, oz = vec(attachment:getOffset())
    local rx, ry, rz = vec(attachment:getRotate())
    local par = Core.IsBody(script) and PAR_AttachCalibrate and PAR_AttachCalibrate.factoryPoints
        and PAR_AttachCalibrate.factoryPoints[point]
    if par and par.off and par.rot then
        ox, oy, oz = par.off[1], par.off[2], par.off[3]
        rx, ry, rz = par.rot[1], par.rot[2], par.rot[3]
    end
    f = { ox, oy, oz, rx, ry, rz, attachment:getScale() }
    factory[script][point] = f
    return f
end

local RAD = 3.14159265358979 / 180

local function rotXYZ(x, y, z)
    local ca, sa = math.cos(x * RAD), math.sin(x * RAD)
    local cb, sb = math.cos(y * RAD), math.sin(y * RAD)
    local cc, sc = math.cos(z * RAD), math.sin(z * RAD)
    return {
        { cb * cc, -cb * sc, sb },
        { ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb },
        { sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb },
    }
end

local function mul(a, b)
    local m = {}
    for i = 1, 3 do
        m[i] = {}
        for j = 1, 3 do
            m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
        end
    end
    return m
end

function Core.Turn(fx, fy, fz, rx, ry, rz)
    if rx == 0 and ry == 0 and rz == 0 then return fx, fy, fz end
    local m = mul(rotXYZ(rx, ry, rz), rotXYZ(fx, fy, fz))
    local y = math.atan2(m[1][3], math.sqrt(m[1][1] * m[1][1] + m[1][2] * m[1][2]))
    local x, z
    if math.abs(m[1][3]) > 0.99999 then
        x = math.atan2(m[3][2], m[2][2])
        z = 0
    else
        x = math.atan2(-m[2][3], m[3][3])
        z = math.atan2(-m[1][2], m[1][1])
    end
    return x / RAD, y / RAD, z / RAD
end

function Core.ApplyValues(ns, point, preview)
    if isServer() then return end
    local v
    if preview ~= nil then
        v = Core.Clean(preview)
    else
        v = Core.ValuesFor(ns, point)
    end
    local cloneId = Core.CloneName(point, ns)
    for _, script in ipairs(Core.ScriptsWith(point)) do
        local base = script:getAttachmentById(point)
        if base then
            local f = factoryOf(script, point, base)
            local clone = script:getAttachmentById(cloneId)
            if not clone then
                clone = ModelAttachment.new(cloneId)
                if base:getBone() then clone:setBone(base:getBone()) end
                clone:setZOffset(base:getZOffset())
                clone:setUpdateConstraint(base:isUpdateConstraint())
                if base:getCanAttach() then clone:setCanAttach(base:getCanAttach()) end
                script:addAttachment(clone)
            end
            if v and Core.IsBody(script) then
                clone:getOffset():set(f[1] + v.ox, f[2] + v.oy, f[3] + v.oz)
                clone:getRotate():set(Core.Turn(f[4], f[5], f[6], v.rx, v.ry, v.rz))
                clone:setScale(f[7] * v.s)
            else
                clone:getOffset():set(f[1], f[2], f[3])
                clone:getRotate():set(f[4], f[5], f[6])
                clone:setScale(f[7])
            end
        end
    end
end

function Core.Register(ns, point)
    local group = Core.Group()
    local list = group and Core.PointLocations(point)
    if not list then return false end
    local fresh = pointMapSize == group:size()
    local cloneId = Core.CloneName(point, ns)
    for _, id in ipairs(list) do
        group:getOrCreateLocation(Core.CloneName(id, ns)):setAttachmentName(cloneId)
    end
    if fresh then pointMapSize = group:size() end
    Core.locs[ns] = Core.locs[ns] or {}
    Core.locs[ns][point] = true
    Core.ApplyValues(ns, point)
    return true
end

function Core.ReapplyAll()
    for ns, points in pairs(Core.locs) do
        for point in pairs(points) do
            Core.ApplyValues(ns, point)
        end
    end
end

function Core.RegisterAll()
    for ns, points in pairs(Core.reg) do
        for point in pairs(points) do
            Core.Register(ns, point)
        end
    end
end

function Core.ResetWorld()
    Core.locs = {}
    scriptIndex = nil
    factory = {}
    bodies = nil
    pointMap = nil
    pointMapSize = nil
end

function Core.Want(chr, base)
    local ns = Core.IdOf(chr)
    local point = Core.PointOf(base)
    if ns and point and Core.IsRegistered(ns, point) then
        return Core.CloneName(base, ns)
    end
    return base
end

function Core.CloneFor(chr, base)
    local ns = Core.IdOf(chr)
    local point = Core.PointOf(base)
    if not ns or not point or not Core.IsRegistered(ns, point) then return nil end
    return Core.CloneName(base, ns)
end

function Core.Target(chr, loc, item)
    local base = Core.BaseOf(loc)
    local clone = Core.CloneFor(chr, base)
    if not clone then return loc end
    if item == nil then
        if loc == base and Core.vanillaGet(chr, clone) then return clone end
        return loc
    end
    if Core.vanillaGet(chr, base) then Core.vanillaSet(chr, base, nil) end
    return clone
end

function Core.BaseTarget(chr, loc, item)
    local base = Core.BaseOf(loc)
    local clone = Core.CloneFor(chr, base)
    if clone and Core.vanillaGet(chr, clone) then Core.vanillaSet(chr, clone, nil) end
    return base
end

function Core.ToBase(chr)
    if not Core.vanillaSet then return end
    local attached = chr:getAttachedItems()
    if not attached then return end
    local moves = {}
    for i = 0, attached:size() - 1 do
        local entry = attached:get(i)
        local loc = entry:getLocation()
        if Core.IsClone(loc) then moves[#moves + 1] = { loc, entry:getItem() } end
    end
    for _, move in ipairs(moves) do
        Core.vanillaSet(chr, Core.BaseOf(move[1]), move[2])
    end
end

function Core.Lookup(chr, loc)
    if Core.IsClone(loc) or instanceof(chr, "IsoAnimal") then return nil end
    local ns = Core.IdOf(chr)
    local point = ns and Core.PointOf(loc)
    if point and Core.IsRegistered(ns, point) then
        return Core.vanillaGet(chr, Core.CloneName(loc, ns))
    end
    return nil
end

function Core.Normalize(chr)
    if not Core.vanillaSet then return end
    local attached = chr:getAttachedItems()
    if not attached then return end
    local entries = {}
    for i = 0, attached:size() - 1 do
        local entry = attached:get(i)
        entries[#entries + 1] = { entry:getLocation(), entry:getItem() }
    end
    for _, entry in ipairs(entries) do
        local loc, item = entry[1], entry[2]
        local base = Core.BaseOf(loc)
        if Core.PointOf(base) then
            local want = Core.Want(chr, base)
            if want ~= loc then
                if Core.moveLogs < 20 then
                    Core.moveLogs = Core.moveLogs + 1
                    print("[TienAttachmentPositions] " .. tostring(chr:getUsername()) .. ": " .. loc .. " -> " .. want)
                end
                Core.vanillaSet(chr, loc, nil)
                Core.vanillaSet(chr, want, item)
            end
        end
    end
end

function Core.Resend(chr)
    if not Core.vanillaSet then return end
    local attached = chr:getAttachedItems()
    if not attached then return end
    local entries = {}
    for i = 0, attached:size() - 1 do
        local entry = attached:get(i)
        if Core.IsClone(entry:getLocation()) then
            entries[#entries + 1] = { entry:getLocation(), entry:getItem() }
        end
    end
    for _, entry in ipairs(entries) do
        Core.vanillaSet(chr, entry[1], entry[2])
    end
end

function Core.EachPlayer(fn)
    local seen = {}
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            seen[player:getUsername() or ""] = true
            fn(player)
        end
    end
    local online = getOnlinePlayers()
    if online then
        for i = 0, online:size() - 1 do
            local player = online:get(i)
            if player and not seen[player:getUsername() or ""] then fn(player) end
        end
    end
end

function Core.ToServer(player, command, args)
    if isClient() then
        sendClientCommand(player, Core.MODULE, command, args)
    elseif Core.Server then
        Core.Server.Handle(player, command, args)
    end
end

function Core.ToClient(player, command, args)
    if isServer() then
        sendServerCommand(player, Core.MODULE, command, args)
    elseif Core.Client then
        Core.Client.Handle(command, args)
    end
end

function Core.ToClients(command, args)
    if isServer() then
        sendServerCommand(Core.MODULE, command, args)
    elseif Core.Client then
        Core.Client.Handle(command, args)
    end
end

local function installWrappers()
    local meta = __classmetatables and IsoPlayer and __classmetatables[IsoPlayer.class]
    local index = meta and meta.__index
    if not index then
        print("[TienAttachmentPositions] IsoPlayer methods are not reachable, attachments stay where the slot mods put them")
        return
    end
    local originals = index.TienAttachmentPositions_Originals
    if not originals then
        originals = { set = index.setAttachedItem, get = index.getAttachedItem }
        if not originals.set or not originals.get then
            print("[TienAttachmentPositions] setAttachedItem / getAttachedItem not found")
            return
        end
        index.TienAttachmentPositions_Originals = originals
    end
    local vanillaSet, vanillaGet = originals.set, originals.get
    Core.vanillaSet, Core.vanillaGet = vanillaSet, vanillaGet

    index.setAttachedItem = function(self, loc, item, ...)
        local fn
        if type(loc) == "string" and not instanceof(self, "IsoAnimal") then
            if isServer() then
                fn = Core.BaseTarget
            elseif self:isLocalPlayer() then
                fn = Core.Target
            end
        end
        if fn then
            local ok, target = pcall(fn, self, loc, item)
            if ok and target then
                loc = target
            elseif not ok then
                print("[TienAttachmentPositions] " .. tostring(target))
            end
        end
        return vanillaSet(self, loc, item, ...)
    end

    index.getAttachedItem = function(self, loc, ...)
        if type(loc) == "string" then
            local ok, found = pcall(Core.Lookup, self, loc)
            if ok and found then return found end
        end
        return vanillaGet(self, loc, ...)
    end
end

installWrappers()
