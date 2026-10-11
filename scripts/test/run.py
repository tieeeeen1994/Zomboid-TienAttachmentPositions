import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("LUPA_PATH", ""))
from lupa import LuaRuntime  # noqa: E402

MOD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Contents", "mods", "TienAttachmentPositions", "42")
LUA = os.path.join(MOD, "media", "lua")
FILES = {
    "core": os.path.join(LUA, "shared", "TienAttachmentPositions_Core.lua"),
    "server": os.path.join(LUA, "server", "TienAttachmentPositions_Server.lua"),
    "client": os.path.join(LUA, "client", "TienAttachmentPositions_Client.lua"),
}
FAILS = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


def runtime(mode):
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.globals().TAP_EN = os.path.join(MOD, "media/lua/shared/Translate/EN/IG_UI.json")
    rt.eval("loadfile")(os.path.join(HERE, "mock.lua"))(mode)
    for name in ("core", "server", "client"):
        if mode == "server" and name == "client":
            continue
        rt.eval("function(p) local f, e = loadfile(p) if not f then error(e) end f() end")(FILES[name])
    return rt


def to_py(v):
    if hasattr(v, "items") and not isinstance(v, (str, bytes)):
        return {k: to_py(x) for k, x in v.items()}
    return v


def to_lua(rt, v):
    if isinstance(v, dict):
        t = rt.table()
        for k, x in v.items():
            t[k] = to_lua(rt, x)
        return t
    return v


L = lambda rt, src: rt.execute(src)  # noqa: E731

# ---------------- single player ----------------
sp = runtime("sp")
L(sp, """
P = M.player("Ann Smith", true); M.locals = { P }
Events.OnInitGlobalModData.fire(true)
Events.OnGameStart.fire()
KNIFE = M.item(1)
P:setAttachedItem("Belt Left", KNIFE)
""")
check(sp.eval("M.locs(P)") == "Belt Left=1", "SP: attach with no adjustment stays on the base location")
L(sp, """
local C = TienAttachmentPositions.Client
C.Edit(P, "belt_left", { ox = 0.1, oy = 0, oz = 0, rx = 0, ry = 45, rz = 0, s = 1.5 })
M.now = 1000
Events.OnTick.fire()
""")
check(sp.eval("M.locs(P)") == "Belt Left@1=1", "SP: first edit assigns id 1 and moves the knife to its own location")
check(sp.eval("M.group:getLocation('Belt Left Upside@1') ~= nil"), "SP: every location of the point gets a copy")
fx = sp.eval("M.female.byId['belt_left@1'].off.X")
rot = sp.eval("(function() local r = M.female.byId['belt_left@1'].rot; local x, y, z = TienAttachmentPositions.Turn(10, 20, 30, 0, 45, 0); return math.abs(r.X - x) + math.abs(r.Y - y) + math.abs(r.Z - z) end)()")
check(abs(fx - 0.2) < 1e-6 and rot < 1e-4, "SP: body copy = base + delta (offset x 0.2, turned 45 around the bone's y)")
check(abs(sp.eval("M.female.byId['belt_left@1'].scale") - 1.5) < 1e-6, "SP: body copy scale x1.5")
check(abs(sp.eval("M.male.byId['belt_left@1'].off.X") - 0.21) < 1e-6, "SP: male body copy uses its own base")
check(sp.eval("M.female.byId['belt_left@1'].bone") == "Bip01_Pelvis", "SP: copy keeps the bone")
k = sp.eval("M.knifeModel.byId['belt_left@1']")
check(k is not None and abs(k.off.X - 0.01) < 1e-6 and abs(k.scale - 0.5) < 1e-6, "SP: item model self point copied unchanged")
check(sp.eval("M.female.byId['belt_left'].off.X") == 0.1, "SP: base point untouched")
check(sp.eval("P:getAttachedItem('Belt Left') == KNIFE"), "SP: getAttachedItem by base name finds the knife on the copy")
L(sp, "P:setAttachedItem('Belt Left', nil)")
check(sp.eval("M.locs(P)") == "", "SP: detach by base name removes it from the copy")
L(sp, "P:setAttachedItem('Belt Left', KNIFE)")
check(sp.eval("M.locs(P)") == "Belt Left@1=1", "SP: re-attach by base name goes to the copy")
L(sp, "P:setAttachedItem('Belt Left Upside', M.item(2))")
check(sp.eval("M.locs(P)") == "Belt Left Upside@1=2,Belt Left@1=1", "SP: other location of the same point uses its own copy")
L(sp, """
local C = TienAttachmentPositions.Client
C.Edit(P, "belt_left", { ox = 0, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 })
M.now = 2000
Events.OnTick.fire()
""")
check(sp.eval("M.locs(P)") == "Belt Left Upside=2,Belt Left=1", "SP: reset moves items back to the base locations")
check(sp.eval("M.moddata.TienAttachmentPositions.pts['1'].belt_left") is None, "SP: reset removes the stored values")
check(sp.eval("M.moddata.TienAttachmentPositions.reg['1'].belt_left") is True, "SP: registration is kept after reset")
check(sp.eval("TienAttachmentPositions.Adjustable('ShoulderHolster')") is False, "SP: clothing-tied point not adjustable")
check(sp.eval("TienAttachmentPositions.Adjustable('belt_left')") is True, "SP: normal point adjustable")
check(sp.eval("TienAttachmentPositions.HasBodyPoint('belt_left')") is True, "SP: body found by name although its script says static (merged mod blocks reset the flag)")
check(sp.eval("TienAttachmentPositions.HasBodyPoint('no_such_point')") is False, "SP: unknown point has no body point")
L(sp, """
local C = TienAttachmentPositions.Client
C.Edit(P, "Alicepack_ulmask", { ox = 9, oy = 0, oz = 0, rx = 999, ry = 0, rz = 0, s = 50 })
M.now = 3000
Events.OnTick.fire()
""")
v = to_py(sp.eval("M.moddata.TienAttachmentPositions.pts['1'].Alicepack_ulmask"))
check(v == {"ox": 0.5, "oy": 0, "oz": 0, "rx": 180, "ry": 0, "rz": 0, "s": 3}, "SP: values clamped " + repr(v))
L(sp, """
local C = TienAttachmentPositions.Client
C.Edit(P, "ShoulderHolster", { ox = 0.1 })
C.Edit(P, "no_such_point", { ox = 0.1 })
M.now = 4000
Events.OnTick.fire()
""")
check(sp.eval("M.moddata.TienAttachmentPositions.pts['1'].ShoulderHolster") is None, "SP: server refuses a clothing-tied point")
check(sp.eval("M.moddata.TienAttachmentPositions.pts['1'].no_such_point") is None, "SP: server refuses an unknown point")
L(sp, "P:setAttachedItem('bowtie', M.item(3))")
check("bowtie=3" in sp.eval("M.locs(P)"), "SP: bowtie untouched")
logs = [l for l in sp.eval("M.logs").values() if not l.startswith("[TienAttachmentPositions] ")]
check(len(logs) == 0, "SP: nothing logged: " + repr(logs))
check(any("bodies: 2" in l for l in sp.eval("M.logs").values()), "SP: index log finds both bodies: " + repr(list(sp.eval("M.logs").values())))

# ---------------- multiplayer ----------------
srv = runtime("server")
ca = runtime("client")
cb = runtime("client")
clients = {"alice": ca, "bob": cb}
L(srv, """
SP_ = {}
SP_.alice = M.player("alice", false); SP_.bob = M.player("bob", false)
M.online = { SP_.alice, SP_.bob }
Events.OnInitGlobalModData.fire(true)
""")
for me, rt in clients.items():
    other = "bob" if me == "alice" else "alice"
    L(rt, f"""
ME = M.player("{me}", true); OTHER = M.player("{other}", false)
M.locals = {{ ME }}; M.online = {{ ME, OTHER }}
ITEMS = {{}}
""")
srv_items = {}


def item_in(rt, iid):
    rt.execute(f"ITEMS[{iid}] = ITEMS[{iid}] or M.item({iid})")
    return rt.eval(f"ITEMS[{iid}]")


DROP_HELLO = [0]


def pump():
    moved = True
    while moved:
        moved = False
        for user, rt in clients.items():
            out = list(rt.eval("M.out").values())
            rt.execute("M.out = {}")
            for msg in out:
                moved = True
                if msg.command == "hello" and DROP_HELLO[0] > 0:
                    DROP_HELLO[0] -= 1
                    continue
                args = to_lua(srv, to_py(msg.args))
                srv.eval("Events.OnClientCommand.fire")(msg.module, msg.command, srv.eval(f"SP_.{user}"), args)
            pkts = list(rt.eval("M.packets").values())
            rt.execute("M.packets = {}")
            for p in pkts:
                moved = True
                iid = p.item
                if iid is not None:
                    srv.execute(f"SITEMS = SITEMS or {{}}; SITEMS[{iid}] = SITEMS[{iid}] or M.item({iid})")
                ok = srv.eval(f"function(loc) return pcall(M.javaSet, SP_.{user}, loc, {('SITEMS[%d]' % iid) if iid is not None else 'nil'}) end")(p.loc)
                for other, ort in clients.items():
                    if other == user:
                        continue
                    target = "OTHER"
                    res = ort.eval(f"function(loc) local ok, e = pcall(M.javaSet, {target}, loc, {('M.item(%d)' % iid) if iid is not None else 'nil'}); if not ok then table.insert(M.errors, tostring(e)) end end")(p.loc)
        out = list(srv.eval("M.out").values())
        srv.execute("M.out = {}")
        for msg in out:
            moved = True
            targets = [msg.to] if msg.to else list(clients)
            for t in targets:
                rt = clients[t]
                rt.eval("Events.OnServerCommand.fire")(msg.module, msg.command, to_lua(rt, to_py(msg.args)))


L(ca, "Events.OnGameStart.fire()")
L(cb, "Events.OnGameStart.fire()")
pump()
L(ca, "ME:setAttachedItem('Belt Left', M.item(10))")
pump()
check(srv.eval("M.locs(SP_.alice)") == "Belt Left=10", "MP: plain attach reaches the server on the base location")
check(cb.eval("M.locs(OTHER)") == "Belt Left=10", "MP: bob sees alice's knife on the base location")
L(ca, """
TienAttachmentPositions.Client.Edit(ME, "belt_left", { ox = 0.1, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 })
M.now = 1000; Events.OnTick.fire()
""")
pump()
check(ca.eval("M.locs(ME)") == "Belt Left@1=10", "MP: alice's own copy after the server's answer")
check(srv.eval("M.locs(SP_.alice)") == "Belt Left@1=10", "MP: server follows")
check(cb.eval("M.locs(OTHER)") == "Belt Left@1=10", "MP: bob sees alice's knife on alice's copy")
check(abs(cb.eval("M.female.byId['belt_left@1'].off.X") - 0.2) < 1e-6, "MP: bob's game has alice's offset")
check(cb.eval("M.female.byId['belt_left'].off.X") == 0.1, "MP: bob's base point untouched")
check(len(list(cb.eval("M.errors").values())) == 0, "MP: no errors on bob " + repr(list(cb.eval("M.errors").values())))
L(cb, "ME:setAttachedItem('Belt Left', M.item(20))")
pump()
check(cb.eval("M.locs(ME)") == "Belt Left=20", "MP: bob without adjustments stays on the base location")
check(ca.eval("M.locs(OTHER)") == "Belt Left=20", "MP: alice sees bob's knife on the base")
# Live edit while dragging: local value applied at once, stale echo ignored.
L(ca, """
local C = TienAttachmentPositions.Client
C.Edit(ME, "belt_left", { ox = 0.3, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 })
M.now = 2000; Events.OnTick.fire()
C.Edit(ME, "belt_left", { ox = 0.4, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 })
""")
check(abs(ca.eval("M.female.byId['belt_left@1'].off.X") - 0.5) < 1e-6, "MP: alice sees her latest drag at once")
pump()
check(abs(ca.eval("M.female.byId['belt_left@1'].off.X") - 0.5) < 1e-6, "MP: stale echo does not pull alice's slider back")
L(ca, "M.now = 3000; Events.OnTick.fire()")
pump()
check(abs(cb.eval("M.female.byId['belt_left@1'].off.X") - 0.5) < 1e-6, "MP: bob gets the final value")
# A third client joins late: alice's items must show on her copy.
cc = runtime("client")
clients["carol"] = cc
L(srv, "SP_.carol = M.player('carol', false); table.insert(M.online, SP_.carol)")
L(cc, """
ME = M.player("carol", true); OTHER = M.player("alice", false)
M.locals = { ME }; M.online = { ME, OTHER }
""")
# Carol's copy of alice was loaded before the mod's data: the clone location was skipped (readInventory).
L(cc, "Events.OnGameStart.fire()")
pump()
check(cc.eval("M.locs(OTHER)") == "Belt Left@1=10", "MP: late joiner gets alice's knife on alice's copy (resend)")
check(len(list(cc.eval("M.errors").values())) == 0, "MP: no errors on carol " + repr(list(cc.eval("M.errors").values())))
# Alice relogs. The server reloads her from its save with the knife on her copy (registered there at world init);
# her fresh game loaded her before the mod's data arrived, so it skipped that location and the knife hangs nowhere.
# The hotbar then re-attaches it by its saved base name, before or after the data arrives.
for when in ("before", "after", "dropped", "connecting"):
    ca2 = runtime("client")
    clients["alice"] = ca2
    L(srv, "SP_.alice = M.player('alice', false); M.online[1] = SP_.alice; SITEMS = SITEMS or {}; SITEMS[10] = SITEMS[10] or M.item(10); M.javaSet(SP_.alice, 'Belt Left@1', SITEMS[10])")
    L(ca2, """
ME = M.player("alice", true); OTHER = M.player("bob", false)
M.locals = { ME }; M.online = { ME, OTHER }
KNIFE = M.item(10)
if WHEN == "connecting" then ME.onlineID = -1 end
Events.OnGameStart.fire()
""".replace("WHEN", repr(when)))
    if when == "connecting":
        L(ca2, "ME:setAttachedItem('Belt Left', KNIFE)")
        check(not any(m.command == "hello" for m in ca2.eval("M.out").values()), "MP relog (no online ID yet): no request before the server knows the player")
        pump()
        L(ca2, "M.now = M.now + 100; Events.OnTick.fire()")
        check(not any(m.command == "hello" for m in ca2.eval("M.out").values()), "MP relog (no online ID yet): still waiting")
        L(ca2, "ME.onlineID = 3; M.now = M.now + 100; Events.OnTick.fire()")
        pump()
    elif when == "dropped":
        DROP_HELLO[0] = 1
        L(ca2, "ME:setAttachedItem('Belt Left', KNIFE)")
        pump()
        check(ca2.eval("M.locs(ME)") == "Belt Left=10", "MP relog (first request dropped): knife on the base until the answer comes")
        L(ca2, "M.now = M.now + 3000; Events.OnTick.fire()")
        pump()
        L(ca2, "M.now = M.now + 2000; Events.OnTick.fire()")
        pump()
    elif when == "before":
        L(ca2, "ME:setAttachedItem('Belt Left', KNIFE)")
        pump()
    else:
        pump()
        L(ca2, "if not ME:getAttachedItem('Belt Left') then ME:setAttachedItem('Belt Left', KNIFE) end")
        pump()
    check(ca2.eval("M.locs(ME)") == "Belt Left@1=10", f"MP relog (hotbar {when} data): alice's knife back on her copy: " + ca2.eval("M.locs(ME)"))
    check(srv.eval("M.locs(SP_.alice)") == "Belt Left@1=10", f"MP relog (hotbar {when} data): server keeps her copy: " + srv.eval("M.locs(SP_.alice)"))
    check(cb.eval("M.locs(OTHER)") == "Belt Left@1=10", f"MP relog (hotbar {when} data): bob still sees her copy: " + cb.eval("M.locs(OTHER)"))
    check(abs(ca2.eval("M.female.byId['belt_left@1'] and M.female.byId['belt_left@1'].off.X or -1") - 0.5) < 1e-6,
          f"MP relog (hotbar {when} data): alice's game has her offset again")
    check(len(list(ca2.eval("M.errors").values())) == 0, f"MP relog (hotbar {when} data): no errors")
ca = ca2
# Reset all on alice.
L(ca, "TienAttachmentPositions.Client.ResetAll(ME)")
pump()
check(ca.eval("M.locs(ME)") == "Belt Left=10", "MP: reset all moves alice's knife back")
check(cb.eval("M.locs(OTHER)") == "Belt Left=10", "MP: bob sees it back on the base")
for name, rt in (("alice", ca), ("bob", cb), ("carol", cc), ("server", srv)):
    logs = [l for l in rt.eval("M.logs").values() if not l.startswith("[TienAttachmentPositions] ")]
    check(len(logs) == 0, f"MP: nothing logged on {name}: {logs!r}")

# Per slot: one setting covers every point the item's hotbar slot can use, bag replacements included.
sl = runtime("sp")
L(sl, """
P = M.player("Dee Jones", true); M.locals = { P }
Events.OnInitGlobalModData.fire(true)
Events.OnGameStart.fire()
local C = TienAttachmentPositions.Client
KNIFE = M.item(1, "SmallBeltLeft")
P:setAttachedItem("Belt Left Upside", KNIFE)
PTS = C.SlotPoints(KNIFE, "belt_left")
C.Edit(P, PTS, { ox = 0.1, oy = 0, oz = 0, rx = 0, ry = 0, rz = 0, s = 1 })
M.now = 1000; Events.OnTick.fire()
RIFLE = M.item(3, "Back")
BACK = C.SlotPoints(RIFLE, "rifle_back")
""")
check(sl.eval("table.concat(PTS, ',')") == "belt_left,walkie_belt_left",
      "slot: the belt's points, without the clothing-hidden one or a missing location: " + sl.eval("table.concat(PTS, ',')"))
check(sl.eval("table.concat(BACK, ',')") == "rifle_back,rifle_back_bag", "slot: Back includes the with-bag points")
check(sl.eval("M.locs(P)") == "Belt Left Upside@1=1", "slot: the knife is on the player's copy")
L(sl, "P:setAttachedItem('Belt Left Upside', nil); WALKIE = M.item(2, 'SmallBeltLeft'); P:setAttachedItem('Walkie Belt Left', WALKIE)")
check(sl.eval("M.locs(P)") == "Walkie Belt Left@1=2", "slot: a walkie attached later goes on the player's copy: " + sl.eval("M.locs(P)"))
check(abs(sl.eval("M.female.byId['walkie_belt_left@1'].off.X") - 0.3) < 1e-6, "slot: the walkie's point got the same move")
check(len(list(sl.eval("M.errors").values())) == 0, "slot: no errors")

# Turning: the player's turn is applied around the bone's axes on top of the spot's own turn, and the result is
# written back as the X, Y, Z angles the game feeds to rotateXYZ (X first, in the point's frame).
import math, random
def rxyz(x, y, z):
    x, y, z = math.radians(x), math.radians(y), math.radians(z)
    rx = [[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]]
    ry = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    rz = [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]]
    return mm(mm(rx, ry), rz)
def mm(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def close(a, b): return max(abs(a[i][j] - b[i][j]) for i in range(3) for j in range(3)) < 1e-6
turn = sp.eval("function(...) return TienAttachmentPositions.Turn(...) end")
random.seed(4)
cases = [((0, 90, 0), (10, 0, 0)), ((0, 90, 0), (0, 0, 10)), ((180, 90, -85), (15, -20, 30)), ((90, -90, 0), (0, 0, -45)),
         ((22, -24, -80), (5, 5, 5)), ((0, 0, 0), (0, 90, 0)), ((10, 80, 0), (0, 10, 0))]
cases += [(tuple(random.uniform(-180, 180) for _ in range(3)), tuple(random.uniform(-180, 180) for _ in range(3)))
          for _ in range(200)]
bad = 0
for f, v in cases:
    e = turn(*f, *v)
    if not close(rxyz(*e), mm(rxyz(*v), rxyz(*f))):
        bad += 1
check(bad == 0, f"turn: the angles written give the bone-axis turn on top of the spot's own ({bad} of {len(cases)} wrong)")
check(turn(22, -24, -80, 0, 0, 0) == (22, -24, -80), "turn: no turn keeps the spot's own angles exactly")
check(not close(rxyz(*turn(0, 90, 0, 10, 0, 0)), rxyz(*turn(0, 90, 0, 0, 0, 10))),
      "turn: X and Z differ on a spot whose own Y turn is 90")

print("\n%d failure(s)" % len(FAILS))
sys.exit(1 if FAILS else 0)
