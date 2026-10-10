if isClient() then return end

require "TienAttachmentPositions_Core"

local Core = TienAttachmentPositions
local Server = {}
Core.Server = Server

local KEY = "TienAttachmentPositions"
local data

local function load()
    data = ModData.getOrCreate(KEY)
    data.ids = data.ids or {}
    data.reg = data.reg or {}
    data.pts = data.pts or {}
    data.next = tonumber(data.next) or 0
    Core.ids, Core.reg, Core.pts = data.ids, data.reg, data.pts
    Core.ResetWorld()
    Core.RegisterAll()
end

local function idFor(user)
    local ns = data.ids[user]
    if ns then return ns end
    data.next = data.next + 1
    ns = string.format("%d", data.next)
    data.ids[user] = ns
    return ns
end

local function countPoints(ns)
    local n = 0
    for _ in pairs(data.pts[ns] or {}) do n = n + 1 end
    return n
end

local function store(user, ns, point, v, seq)
    data.reg[ns] = data.reg[ns] or {}
    data.reg[ns][point] = true
    data.pts[ns] = data.pts[ns] or {}
    data.pts[ns][point] = v
    Core.Register(ns, point)
    Core.ToClients("pt", { u = user, n = ns, p = point, v = v, seq = seq })
end

local function validPoint(point)
    return type(point) == "string" and #point <= 128 and Core.Adjustable(point) and Core.PointLocations(point) ~= nil
end

function Server.Handle(player, command, args)
    if not data or not player then return end
    args = args or {}
    local user = player:getUsername()
    if not user or user == "" then return end

    if command == "hello" then
        Core.ToClient(player, "all", { ids = data.ids, reg = data.reg, pts = data.pts })
        if isServer() then
            local online = getOnlinePlayers()
            for i = 0, online:size() - 1 do
                local other = online:get(i)
                local ns = other and other:getUsername() ~= user and data.ids[other:getUsername()]
                if ns and data.reg[ns] then
                    sendServerCommand(other, Core.MODULE, "resend", {})
                end
            end
        end
    elseif command == "set" then
        local point = args.p
        if not validPoint(point) then return end
        local ns = idFor(user)
        local v = Core.Clean(args.v)
        if v and not (data.pts[ns] and data.pts[ns][point]) and countPoints(ns) >= Core.MAX_POINTS then return end
        store(user, ns, point, v, tonumber(args.seq))
    elseif command == "resetAll" then
        local ns = data.ids[user]
        if not ns or not data.pts[ns] then return end
        local points = {}
        for point in pairs(data.pts[ns]) do points[#points + 1] = point end
        for _, point in ipairs(points) do
            store(user, ns, point, nil, tonumber(args.seq))
        end
    end
end

Events.OnInitGlobalModData.Add(load)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Core.MODULE then return end
    Server.Handle(player, command, args)
end)
