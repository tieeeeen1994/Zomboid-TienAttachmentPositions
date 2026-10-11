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
    local players = 0
    for _ in pairs(data.ids) do players = players + 1 end
    print("[TienAttachmentPositions] " .. Core.VERSION .. " loaded the positions of " .. players .. " players")
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

local function store(user, ns, points, v, seq)
    data.reg[ns] = data.reg[ns] or {}
    data.pts[ns] = data.pts[ns] or {}
    for _, point in ipairs(points) do
        data.reg[ns][point] = true
        data.pts[ns][point] = v
        Core.Register(ns, point)
    end
    Core.ToClients("pt", { u = user, n = ns, ps = points, v = v, seq = seq })
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
        local ns = data.ids[user]
        local spots = 0
        for _ in pairs(ns and data.pts[ns] or {}) do spots = spots + 1 end
        print("[TienAttachmentPositions] " .. Core.VERSION .. " sending positions to " .. user .. " (their spots: " .. spots
            .. ", their version: " .. tostring(args.v) .. ")")
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
        local asked = type(args.ps) == "table" and args.ps or { args.p }
        local v = Core.Clean(args.v)
        local ns = data.ids[user]
        local have = ns and countPoints(ns) or 0
        local points, seen = {}, {}
        for _, point in pairs(asked) do
            if #points >= Core.MAX_SLOT_POINTS then break end
            if validPoint(point) and not seen[point] then
                seen[point] = true
                local known = ns and data.pts[ns] and data.pts[ns][point]
                if not v or known or have < Core.MAX_POINTS then
                    if v and not known then have = have + 1 end
                    points[#points + 1] = point
                end
            end
        end
        if #points > 0 then store(user, idFor(user), points, v, tonumber(args.seq)) end
    elseif command == "resetAll" then
        local ns = data.ids[user]
        if not ns or not data.pts[ns] then return end
        local points = {}
        for point in pairs(data.pts[ns]) do points[#points + 1] = point end
        if #points > 0 then store(user, ns, points, nil, tonumber(args.seq)) end
    end
end

Events.OnInitGlobalModData.Add(load)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Core.MODULE then return end
    Server.Handle(player, command, args)
end)
