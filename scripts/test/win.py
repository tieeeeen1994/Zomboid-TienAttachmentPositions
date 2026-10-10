import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("LUPA_PATH", ""))
from lupa import LuaRuntime
MOD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "Contents", "mods", "TienAttachmentPositions", "42")
for fh, sw in ((15, 1920), (23, 1920), (32, 1920), (48, 1920), (48, 1280)):
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.globals().TAP_EN = os.path.join(MOD, "media/lua/shared/Translate/EN/IG_UI.json")
    rt.eval("loadfile")(os.path.join(HERE, "mock.lua"))("sp")
    for p in ("shared/TienAttachmentPositions_Core.lua", "server/TienAttachmentPositions_Server.lua", "client/TienAttachmentPositions_Client.lua"):
        rt.eval("function(p) local f, e = loadfile(p) if not f then error(e) end f() end")(os.path.join(MOD, "media/lua", p))
    rt.execute('P = M.player("Ann", true); M.locals = { P }; Events.OnInitGlobalModData.fire(true); Events.OnGameStart.fire(); P:setAttachedItem("Belt Left", M.item(1))')
    rt.execute(f"SCREEN_W = {sw}")
    w, h, problems, ox, s, n = rt.eval("loadfile")(os.path.join(HERE, "window.lua"))(MOD, fh)
    rt.execute("M.now = 1000; Events.OnTick.fire()")
    print(f"font {fh} screen {sw}: {w:.0f}x{h:.0f}, {n} children, ox={ox} s={s}, problems: {problems or 'none'}, knife at {rt.eval('M.locs(P)')}")
