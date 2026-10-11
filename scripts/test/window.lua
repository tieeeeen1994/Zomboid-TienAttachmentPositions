-- Builds the window at one font size and checks the layout; run after mock.lua + the mod files (sp).
local modDir, fontH = ...
local charW = fontH * 0.5
assert(loadfile(TAP_TEST_DIR .. "/ui_mock.lua"))(modDir, fontH)

local W = TienAttachmentPositionsWindow:new(P, { "belt_left" }, "Hunting Knife - Belt Left (a slot name long enough to wrap onto a second line at small sizes)")
W:initialise()
W:instantiate()
W:createChildren()
W:addToUIManager()
TienAttachmentPositions.Client.window = W

local problems = {}
for _, c in ipairs(W.children) do
    if c.x < 0 or c.x + c.width > W.width + 0.5 then problems[#problems + 1] = "x overflow: " .. tostring(c.name or c.title or c.key) .. " " .. c.x .. "+" .. c.width .. " > " .. W.width end
    if c.y + c.height > W.height + 0.5 then problems[#problems + 1] = "y overflow: " .. tostring(c.name or c.title or c.key) end
end
for i, a in ipairs(W.children) do
    for j, b in ipairs(W.children) do
        if i < j and a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height then
            problems[#problems + 1] = "overlap: " .. tostring(a.name or a.title or a.key) .. " / " .. tostring(b.name or b.title or b.key)
        end
    end
end
W.rows.ox.slider:setCurrentValue(0.123)
W.rows.s.slider:setCurrentValue(2)
local ns = TienAttachmentPositions.IdOf(P)
return W.width, W.height, table.concat(problems, "; "), W.rows.ox.value.name, W.rows.s.value.name, #W.children
