"""The real w_store door + the real takeSupplies guards, run against a fake framework."""
import os, re, sys
from lupa.lua54 import LuaRuntime
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"F:\Server RedM\MajestyRP\FILSE\resources\[wraith]\w_medic"
src  = re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, "server", "main.lua"), encoding="utf-8-sig").read())

def cut(a, b): return src[src.index(a):src.index(b)]
# storeUp .. reloadStore are the w_store helpers the door needs. The seeder and its boot
# thread are left out on purpose: they touch MySQL, which this harness has no database for.
STORE  = cut("local function storeUp()", "--- The clerk of a hospital's pharmacy")
DOOR   = cut("--- The armory prompt's door when w_store is the shelf", "local function activeBag()")
HANDOUT = cut("local function takeSupplies(src)", "--- The armory prompt. Which shelf it opens")
CB     = cut("--- The armory prompt. Which shelf it opens", "AddEventHandler('playerDropped'")

CFG = r"""
Config = {
    Locations = { armory = {
        { coords = { x = -289.913, y = 816.26,  z = 119.38 }, city = 'Valentine'   },
        { coords = { x = 2382.31,  y = -1372.55, z = 46.55  }, city = 'Saint Denis' },
        { coords = { x = -3651.38, y = -2653.74, z = -13.45 }, city = 'Armadillo'   },
    } },
    Pharmacy = {
        enabled = true, useStore = true, openDistance = 6.0,
        storePrices = { bandage = 0 }, cashier = { model = 'm', scenario = 's' },
        windowMinutes = 60, maxPerWindow = 3, maxPerVisit = 2,
        perVisit = { bandage = 1 }, stock = { bandage = 20 },
    },
}
local shelfStock, shelfTaken, PlayerInjuries, PlayerWeaponWounds = {}, {}, {}, {}
local printed = {}
w = {}
function say() end
function print() end
function dprint() end
function dprintErr() end
function refillShelf() end
function setupPharmacy() return false, 'store' end
function activeBag() return nil end
function w.notify() end
"""
fails = []
def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok: fails.append(label)

VAL = (-289.913, 816.26, 119.38)

def build(job="doctor", onduty=True, at=VAL, stores=None, store_up=True, use_store=True):
    lua = LuaRuntime()
    g = lua.globals()
    log = {"opened": [], "added": []}
    def T(**kw):
        t = lua.table()
        for k, v in kw.items(): t[k] = v
        return t
    lua.execute(CFG)
    g.GetResourceState = lambda n: "started" if (n == "w_store" and store_up) else "missing"
    g.GetPlayerPed = lambda src: 1
    mkv = lua.eval("function(x,y,z) local V={} V.__index=V "
                   "V.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}, getmetatable(a)) end "
                   "V.__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end "
                   "return setmetatable({x=x,y=y,z=z}, V) end")
    g.GetEntityCoords = lambda src: mkv(*at)
    g.vector3 = mkv
    shelf_list = lua.table()
    for i, s in enumerate(stores if stores is not None else [T(id=1, name="Valentine Pharmacy"),
                                     T(id=2, name="Saint Denis Pharmacy"),
                                     T(id=3, name="Armadillo Pharmacy")], 1):
        shelf_list[i] = s
    g.exports = T(
        w_store=T(GetStores=lambda *_: shelf_list, GetStore=lambda *a: None),
        w_lib=T(InvCanCarry=lambda *a: True,
                InvAddItem=lambda *a: (log["added"].append(a[2]), True)[1]))
    lua.execute("json = { encode = function(v) return '{}' end }")
    def get_player(src, *r):
        if not job: return None
        return T(PlayerData=T(job=T(name=job, onduty=onduty, grade=T(level=0))))
    g.WCore = T(Functions=T(GetPlayer=get_player))
    g.__cb = lua.table()
    g.w.callback = T(register=lambda n, f: g.__cb.__setitem__(n, f))
    g.w["callback"]["await"] = lambda n, *a: (g.__cb[n](1, *a) if n in g.__cb
                                              else T(ok=False, error="missing"))
    g.__cb["w_store:server:open"] = lambda src, sid, view: (
        log["opened"].append((int(sid), view)), T(ok=True))[1]
    lua.execute("TriggerClientEvent = function() end\nGetGameTimer = function() return 1000 end\n")
    lua.execute("local CFG = Config\nConfig.Pharmacy.useStore = %s\nlocal shelfStock = { bandage = 20 }\nlocal shelfTaken = {}\n"
             % ("true" if use_store else "false")
             + STORE + DOOR + HANDOUT + CB)
    return lua, g, log

def open_(g, city): return g.__cb["w_medic:takeSupplies"](1, city)

print("\n--- the w_store door ---")
lua, g, log = build()
r = open_(g, "Valentine")
# 2026-10-14: the page is w_store's own (its prompt on the pharmacist); the cabinet, once its
# door checks pass, sends the doctor to him instead of a server-side open that never worked
check("a doctor on duty passes the door", r["error"] == "use_clerk", str(r["error"]))
check("and is sent to the pharmacist (no server-side open)", r["ok"] is False and log["opened"] == [], str(log["opened"]))

lua, g, log = build(job="unemployed")
r = open_(g, "Valentine")
check("a civilian is refused", r["ok"] is False)
check("reason not_ems", r["error"] == "not_ems", str(r["error"]))

lua, g, log = build(onduty=False)
r = open_(g, "Valentine")
check("an off-duty doctor is refused", r["ok"] is False)
check("reason not_on_duty", r["error"] == "not_on_duty", str(r["error"]))

lua, g, log = build(at=(0.0, 0.0, 0.0))
r = open_(g, "Valentine")
check("a doctor across the map is refused", r["ok"] is False)
check("reason too_far", r["error"] == "too_far", str(r["error"]))

lua, g, log = build()
r = open_(g, "Saint Denis")
check("claiming another hospital is refused", r["ok"] is False)
check("reason too_far", r["error"] == "too_far", str(r["error"]))
check("and w_store was never asked", log["opened"] == [], str(log["opened"]))

lua, g, log = build(store_up=False)
r = open_(g, "Valentine")
check("w_store down does NOT break the cabinet: it serves by hand", r["ok"] is True, str(r["ok"]))
check("and w_store was never asked", log["opened"] == [], str(log["opened"]))

print("\n--- each hospital opens its own shelf ---")
for city, sid, pos in (("Valentine", 1, VAL),
                       ("Saint Denis", 2, (2382.31, -1372.55, 46.55)),
                       ("Armadillo", 3, (-3651.38, -2653.74, -13.45))):
    lua, g, log = build(at=pos)
    r = open_(g, city)
    check("%-11s -> #%d passes its own door" % (city, sid), r["error"] == "use_clerk",
          "error=%s" % r["error"])

print("\n--- the handout path (w_store off, or useStore false) ---")
lua, g, log = build(use_store=False)
r = open_(g, "Valentine")
check("a doctor at the counter is served by hand", r["ok"] is True, str(r["ok"]))
check("and w_store was never involved", log["opened"] == [], str(log["opened"]))

lua, g, log = build(use_store=False, at=(0.0, 0.0, 0.0))
r = open_(g, "Valentine")
check("the handout now refuses a doctor across the map", r["ok"] is False)
check("reason too_far", r["error"] == "too_far", str(r["error"]))
check("and nothing was handed over", log["added"] == [], str(log["added"]))

lua, g, log = build(use_store=False, job="unemployed")
r = open_(g, "Valentine")
check("the handout refuses a civilian too", r["ok"] is False)
check("reason not_ems", r["error"] == "not_ems", str(r["error"]))

lua, g, log = build(store_up=False)
r = open_(g, "Valentine")
check("w_store down falls back to the handout (the cabinet stays open)", r["ok"] is True, str(r["ok"]))
check("reason is 'given', not an error", r["error"] == "given", str(r["error"]))
check("and w_store was never asked", log["opened"] == [], str(log["opened"]))

print("\n--- a shelf w_store does not hold ---")
lua, g, log = build(stores=[])
r = open_(g, "Valentine")
check("a shelf w_store does not hold is named as such", r["ok"] is False and r["error"] == "store_unknown",
      str(r["error"]))

print("\n%d check(s) failed" % len(fails))
for f in fails: print("  ! " + f)
sys.exit(1 if fails else 0)
