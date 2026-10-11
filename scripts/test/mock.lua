-- Mock of the Java side the mod touches. mode: "sp", "server" or "client".
local mode = ...
TAP_EN = TAP_EN or "../../Contents/mods/TienAttachmentPositions/42/media/lua/shared/Translate/EN/IG_UI.json"
M = { mode = mode, out = {}, packets = {}, errors = {}, now = 0, locals = {}, online = {}, logs = {} }

local realPrint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end M.logs[#M.logs + 1] = table.concat(t, " ") end

local function newEvent()
    local e = { fns = {} }
    function e.Add(f) table.insert(e.fns, f) end
    function e.Remove(f) for i, g in ipairs(e.fns) do if g == f then table.remove(e.fns, i) return end end end
    function e.fire(...) for _, f in ipairs(e.fns) do f(...) end end
    return e
end
Events = setmetatable({}, { __index = function(t, k) local e = newEvent() rawset(t, k, e) return e end })

local function vec3(x, y, z)
    local v = { X = x or 0, Y = y or 0, Z = z or 0 }
    function v:x() return self.X end
    function v:y() return self.Y end
    function v:z() return self.Z end
    function v:set(a, b, c) self.X, self.Y, self.Z = a, b, c end
    return v
end

ModelAttachment = { new = function(id)
    local a = { id = id, off = vec3(), rot = vec3(), scale = 1, zoff = 0, uc = false }
    function a:getId() return self.id end
    function a:getOffset() return self.off end
    function a:getRotate() return self.rot end
    function a:getScale() return self.scale end
    function a:setScale(s) self.scale = s end
    function a:getBone() return self.bone end
    function a:setBone(b) self.bone = b end
    function a:getZOffset() return self.zoff end
    function a:setZOffset(z) self.zoff = z end
    function a:isUpdateConstraint() return self.uc end
    function a:setUpdateConstraint(b) self.uc = b end
    function a:getCanAttach() return self.can end
    function a:setCanAttach(c) self.can = c end
    return a
end }

local function jlist(t)
    local l = { t = t or {} }
    function l:size() return #self.t end
    function l:get(i) return self.t[i + 1] end
    return l
end

local function modelScript(name, static)
    local ms = { key = name, name = name, static = static, list = {}, byId = {} }
    function ms:getName() return self.name end
    function ms:isStatic() return self.static end
    function ms:getAttachmentCount() return #self.list end
    function ms:getAttachment(i) return self.list[i + 1] end
    function ms:getAttachmentById(id) return self.byId[id] end
    function ms:addAttachment(a) table.insert(self.list, a) self.byId[a:getId()] = a return a end
    return ms
end

local function point(ms, id, bone, o, r, s)
    local a = ModelAttachment.new(id)
    a:setBone(bone)
    a:getOffset():set(o[1], o[2], o[3])
    a:getRotate():set(r[1], r[2], r[3])
    a:setScale(s or 1)
    ms:addAttachment(a)
end

M.female = modelScript("FemaleBody", true)
M.male = modelScript("MaleBody", true)
M.knifeModel = modelScript("Knife", true)
-- Merged script blocks reset the body scripts: static again and the name nulled (ModelScript.reset).
M.female.name = nil
M.male.name = nil
point(M.female, "belt_left", "Bip01_Pelvis", { 0.1, 0.2, 0.3 }, { 10, 20, 30 })
point(M.male, "belt_left", "Bip01_Pelvis", { 0.11, 0.21, 0.31 }, { 11, 21, 31 })
point(M.female, "ShoulderHolster", "Bip01_Spine", { 0, 0, 0 }, { 0, 0, 0 })
point(M.female, "Alicepack_ulmask", "Bip01_Spine", { 0.5, 0, 0 }, { 0, 90, 0 })
point(M.knifeModel, "belt_left", nil, { 0.01, 0.02, 0.03 }, { 1, 2, 3 }, 0.5)
local scripts = jlist({ M.female, M.male, M.knifeModel })
getScriptManager = function() return { getAllModelScripts = function() return scripts end, getModelScript = function(_, n) for _, s in ipairs(scripts.t) do if s.key == n then return s end end return nil end } end

local function location(id)
    local l = { id = id }
    function l:getId() return self.id end
    function l:getAttachmentName() return self.att end
    function l:setAttachmentName(a) self.att = a end
    return l
end
M.group = { locs = {} }
local group = M.group
function group:size() return #self.locs end
function group:getLocationByIndex(i) return self.locs[i + 1] end
function group:getLocation(id) for _, l in ipairs(self.locs) do if l.id == id then return l end end return nil end
function group:getOrCreateLocation(id) local l = self:getLocation(id) if not l then l = location(id) table.insert(self.locs, l) end return l end
AttachedLocations = { getGroup = function() return group end }
group:getOrCreateLocation("Belt Left"):setAttachmentName("belt_left")
group:getOrCreateLocation("Belt Left Upside"):setAttachmentName("belt_left")
group:getOrCreateLocation("Holster Shoulder"):setAttachmentName("ShoulderHolster")
group:getOrCreateLocation("bowtie"):setAttachmentName("bowtie")
group:getOrCreateLocation("AlicepackulMask"):setAttachmentName("Alicepack_ulmask")

ResourceLocation = { of = function(id) return { path = id:lower() } end }
ItemBodyLocation = { get = function(rl) if rl.path == "shoulderholster" then return {} end return nil end }

local index = {}
IsoPlayer = { class = "IsoPlayerClass" }
__classmetatables = { IsoPlayerClass = { __index = index } }

local function attachedItems()
    local ai = { items = {} }
    function ai:size() return #self.items end
    function ai:get(i) local e = self.items[i + 1] return { getLocation = function() return e.loc end, getItem = function() return e.item end } end
    function ai:getLocation(item) for _, e in ipairs(self.items) do if e.item == item then return e.loc end end return nil end
    return ai
end

-- What Java's IsoGameCharacter.setAttachedItem does, called from Java packet handlers (never through the Lua wrapper).
function M.javaSet(self, loc, item)
    if not group:getLocation(loc) then error("no such location \"" .. tostring(loc) .. "\"") end
    local items = self.ai.items
    for i = #items, 1, -1 do if items[i].loc == loc then table.remove(items, i) end end
    if item then
        for i = #items, 1, -1 do if items[i].item == item then table.remove(items, i) end end
        table.insert(items, { loc = loc, item = item })
    end
    self.resets = self.resets + 1
    if M.mode == "client" and self.localP then table.insert(M.packets, { user = self.user, loc = loc, item = item and item.id or nil }) end
end
index.setAttachedItem = function(self, loc, item) return M.javaSet(self, loc, item) end
index.getAttachedItem = function(self, loc)
    if loc == nil then error("locationId is null") end
    if not group:getLocation(loc) then error("no such location \"" .. tostring(loc) .. "\"") end
    for _, e in ipairs(self.ai.items) do if e.loc == loc then return e.item end end
    return nil
end
M.index = index

local pmethods = {
    getUsername = function(s) return s.user end,
    isLocalPlayer = function(s) return s.localP end,
    getOnlineID = function(s) return s.onlineID or 0 end,
    getAttachedItems = function(s) return s.ai end,
    resetModelNextFrame = function(s) s.resets = s.resets + 1 end,
}
function M.player(user, isLocal)
    local p = { user = user, localP = isLocal, ai = attachedItems(), resets = 0 }
    return setmetatable(p, { __index = function(_, k) return index[k] or pmethods[k] end })
end
function M.item(id) return { isItem = true, id = id, getDisplayName = function() return "Item " .. id end } end
function M.locs(p) local t = {} for _, e in ipairs(p.ai.items) do t[#t + 1] = e.loc .. "=" .. tostring(e.item and e.item.id) end table.sort(t) return table.concat(t, ",") end

instanceof = function(o, cls)
    if cls == "InventoryItem" then return type(o) == "table" and o.isItem == true end
    return false
end
isClient = function() return mode == "client" end
isServer = function() return mode == "server" end
getNumActivePlayers = function() return #M.locals end
getSpecificPlayer = function(i) return M.locals[i + 1] end
getOnlinePlayers = function() if mode == "sp" then return nil end return jlist(M.online) end
getTimestampMs = function() return M.now end
sendClientCommand = function(player, module, command, args) table.insert(M.out, { kind = "c", user = player.user, module = module, command = command, args = args }) end
sendServerCommand = function(a, b, c, d)
    if type(a) == "string" then table.insert(M.out, { kind = "s", module = a, command = b, args = c })
    else table.insert(M.out, { kind = "s", to = a.user, module = b, command = c, args = d }) end
end
local moddata = {}
ModData = { getOrCreate = function(k) moddata[k] = moddata[k] or {} return moddata[k] end }
M.moddata = moddata
local EN = {}
do
    local fh = io.open(TAP_EN, "r")
    if fh then for k, v in fh:read("a"):gmatch('"([%w_]+)":%s*"(.-)"') do EN[k] = v end fh:close() end
end
getText = function(k) return EN[k] or k end
getTextOrNull = function() return nil end
require = function() end
