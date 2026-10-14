"""The desk treatment: what a patient can and cannot get without a medic, run for real."""
import os, re, sys
from lupa.lua54 import LuaRuntime
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"F:\Server RedM\MajestyRP\FILSE\resources\[wraith]\w_medic"
cli  = re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, "client", "main.lua"), encoding="utf-8-sig").read())
srv  = re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, "server",  "main.lua"), encoding="utf-8-sig").read())

def cut(s, a, b): return s[s.index(a):s.index(b)]
CHECKIN = cut(cli, "function CheckIn()", "-- Lie in the closest bed")
LIE     = cut(cli, "function LieInBed()", "-- Events")
BED     = cut(srv, "RegisterNetEvent('hospital:server:SendToBed'", "--- The respawn point nearest to where the player lies")

fails = []
def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok: fails.append(label)

def run(cfg_only, code, doctor=False, onduty=False, doctors=0, bed_owner=None):
    lua = LuaRuntime(); g = lua.globals(); log = {"paged": 0, "beds": 0, "notices": []}
    def T(**kw):
        t = lua.table()
        for k, v in kw.items(): t[k] = v
        return t
    g.Config = T(OnlyTouchedByDoctors=cfg_only, MinimalDoctors=2)
    g.doctorCount = doctors
    g.closestBed = 1
    g.locale = lambda k: k
    g.GetAvailableBed = lambda *a: 1
    g.WCore = T(Functions=T(
        Notify=lambda *a: log["notices"].append(a[0]),
        Progressbar=lambda *a, **k: None))
    g.TriggerServerEvent = lambda ev, *a: log.update(paged=log["paged"] + 1) if "Alert" in ev else None
    g.TriggerEvent = lambda *a: None
    g.Wait = lambda *a: None
    g.WCore["Functions"]["Notify"] = lambda *a: log["notices"].append(a[0])
    g.closeBed = lambda *a: None
    # server side
    g.TriggerClientEvent = lambda *a: log.update(beds=log["beds"] + 1)
    g.occupyBed = lambda *a: None
    g.scheduleBedHeal = lambda *a: None
    g.payHospital = lambda *a: None
    g.validBed = lambda *a: True
    g.atHospital = lambda *a: True
    g.bedBySrc = lua.table()
    if bed_owner: g.bedBySrc[1] = bed_owner
    g.WCore["Functions"]["GetPlayer"] = lambda src: (
        None if not doctor else T(PlayerData=T(job=T(name="doctor", onduty=onduty))))
    g.source = 1
    lua.execute(code)
    return lua, g, log

print("\n--- Config.OnlyTouchedByDoctors = true (the new default) ---")
for fn, label in ((CHECKIN, "CheckIn"), (LIE, "LieInBed")):
    name = label
    lua, g, log = run(True, fn)
    g[name]()
    check("%-9s pages the doctors" % name, log["paged"] == 1, "paged=%d" % log["paged"])

lua, g, log = run(True, CHECKIN, doctors=0)
g.CheckIn()
check("with nobody on duty it says so", "error.doctors_only" in log["notices"], str(log["notices"]))
check("and still pages", log["paged"] == 1)

lua, g, log = run(True, CHECKIN, doctors=5)
g.CheckIn()
check("with doctors on duty no complaint", log["notices"] == [], str(log["notices"]))

print("\n--- and nobody is healed by the machine either ---")
def bed_call(doctor, onduty, owner=None, bedId=1, isRevive=True):
    lua = LuaRuntime(); g = lua.globals(); log = {"beds":0,"heal":0,"bill":0}
    def T(**kw):
        t = lua.table()
        for k,v in kw.items(): t[k]=v
        return t
    beds = T()
    beds[1] = T(coords=T(x=0.0,y=0.0,z=0.0), taken=False)
    g.Config = T(OnlyTouchedByDoctors=True, Locations=T(beds=beds))
    g.WCore = T(Functions=T(GetPlayer=lambda s: (None if not doctor else
              T(PlayerData=T(job=T(name="doctor", onduty=onduty))))))
    g.bedBySrc = lua.table()
    if owner: g.bedBySrc[1] = owner
    g.source = 1
    g.occupyBed = lambda *a: None
    g.scheduleBedHeal = lambda *a: log.update(heal=log["heal"]+1)
    g.payHospital = lambda *a: log.update(bill=log["bill"]+1)
    g.TriggerClientEvent = lambda *a: log.update(beds=log["beds"]+1)
    g.validBed = lambda b: b == 1
    g.atHospital = lambda *a: True
    lua.execute("HANDLER = nil")
    # `RegisterNetEvent('name', function(...) ... end)` -> `HANDLER = function(...) ... end`
    body = BED[BED.index(", function") + 2:].rstrip()
    assert body.endswith(")"), body[-20:]
    lua.execute("HANDLER = " + body[:-1].rstrip())
    g.HANDLER(bedId, isRevive)
    return log

log = bed_call(doctor=False, onduty=False)
check("a patient is NOT put in a bed by himself", log["beds"] == 0, str(log))
check("and is NOT healed by the hospital", log["heal"] == 0, str(log))
check("and is NOT billed", log["bill"] == 0, str(log))

log = bed_call(doctor=True, onduty=True)
check("a medic on duty is still put in a bed (the bed stay still works)", log["beds"] == 1, str(log))

log = bed_call(doctor=True, onduty=True, owner=2)
check("a second request while already in a bed is dropped (no double bill)", log["bill"] == 0, str(log))

print("\n--- the old behaviour is still one flag away ---")
lua, g, log = run(False, CHECKIN, doctors=0)
g.CheckIn()
check("with the flag off the bed still takes him (as before)", log["paged"] == 0, "paged=%d" % log["paged"])

print("\n%d check(s) failed" % len(fails))
for f in fails: print("  ! " + f)
sys.exit(1 if fails else 0)
