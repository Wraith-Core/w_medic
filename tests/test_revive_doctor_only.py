"""Only a doctor on duty revives (owner, 2026-10-14): the revive, the bystander kit, the syringe item,
and the admins' /medrevive switched off (Config.AdminRevive)."""
import locale, os, re, sys
locale.setlocale(locale.LC_ALL, "C")
from lupa.lua54 import LuaRuntime
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"F:\Server RedM\MajestyRP\FILSE\resources\[wraith]\w_medic"
MAIN = open(os.path.join(ROOT, "server", "main.lua"), encoding="utf-8-sig").read()
def cut(a, b):
    i = MAIN.index(a)
    return MAIN[i:MAIN.index(b, i)]
REVIVE = cut("RegisterNetEvent('hospital:server:RevivePlayer'", "RegisterNetEvent('hospital:server:SendDoctorAlert'")
FIRSTAID = cut("RegisterNetEvent('hospital:server:UseFirstAid'", "RegisterNetEvent('hospital:server:CanHelp'")
SYRINGE = cut("WCore.Functions.CreateUseableItem(Config.ItemNames.revive", "-- ── the doctor's job label")
MEDREVIVE = cut("-- (registered only with Config.AdminRevive", "WCore.Commands.Add(\"setpain\"")

fails = []
def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok: fails.append(label)

cfg = open(os.path.join(ROOT, "config.lua"), encoding="utf-8-sig").read()
check("Config.AdminRevive is off", re.search(r"^Config\.AdminRevive\s*=\s*false", cfg, re.M) is not None)

lua = LuaRuntime()
lua.execute(r"""
Config = { ItemNames = { revive = 'syringe' }, AdminRevive = false }
NET, ITEMS, CMDS, NOTES, CLIENT, KITS = {}, {}, {}, {}, {}, 0
P = {
  [1] = { job = { name = 'doctor', onduty = true } },
  [2] = { job = { name = 'doctor', onduty = false } },
  [3] = { job = { name = 'unemployed', onduty = false }, admin = true },
  [9] = { job = { name = 'unemployed' }, metadata = { isdead = true } },
}
local function player(s)
  local p = P[tonumber(s)]
  if not p then return nil end
  return { PlayerData = { source = tonumber(s), job = p.job, metadata = p.metadata or {} },
           Functions = { RemoveItem = function() KITS = KITS + 1 return true end } }
end
WCore = { Functions = { GetPlayer = player, CreateUseableItem = function(n, f) ITEMS[n] = f end },
          Commands = { Add = function(n) CMDS[n] = true end } }
function RegisterNetEvent(n, f) NET[n] = f end
function TriggerClientEvent(n, s) CLIENT[#CLIENT + 1] = { n, s } end
w = { notify = function(s, d) NOTES[#NOTES + 1] = { s, d.description } end }
function withinReach() return true end
function refillNeeds() end
function payDoctor() end
-- 1.0.2: the revive also tells w_level (levelXp, keyed by downSince): both live outside the slice cut here
downSince = {}
LEVEL = {}
function levelXp(src, activity, ctx, key) LEVEL[#LEVEL + 1] = { src, activity, key } end
TREAT_REACH = 10.0
function fire(n, s, ...) source = s NOTES, CLIENT, KITS = {}, {}, 0 return NET[n](...) end
function revived() for _, c in ipairs(CLIENT) do if c[1] == 'hospital:client:Revive' then return true end end return false end
function said(key) for _, n in ipairs(NOTES) do if n[2] == key then return true end end return false end
""")
lua.execute(REVIVE)
lua.execute(FIRSTAID)
lua.execute(SYRINGE)
lua.execute(MEDREVIVE)

print("\n--- the revive ---")
lua.execute("fire('hospital:server:RevivePlayer', 1, 9)")
check("a doctor on duty revives", lua.eval("revived()") is True and lua.eval("KITS") == 1)
lua.execute("fire('hospital:server:RevivePlayer', 2, 9)")
check("a doctor off duty does not (told to clock in)", lua.eval("revived()") is False and lua.eval("said('error.not_on_duty')") is True)
check("and his kit is kept", lua.eval("KITS") == 0)
lua.execute("fire('hospital:server:RevivePlayer', 3, 9)")
check("an admin who is not a doctor does not", lua.eval("revived()") is False and lua.eval("said('error.not_ems')") is True)

print("\n--- the syringe from the bag ---")
lua.execute("source = 3 NOTES, CLIENT = {}, {} ITEMS.syringe(3, { name = 'syringe' })")
check("a non-doctor using a syringe is refused", lua.eval("#CLIENT") == 0 and lua.eval("said('error.not_ems')") is True)
lua.execute("NOTES, CLIENT = {}, {} ITEMS.syringe(1, { name = 'syringe' })")
check("a doctor on duty using it goes on to the patient", lua.eval("CLIENT[1] and CLIENT[1][1]") == "hospital:client:UseFirstAid")
lua.execute("fire('hospital:server:UseFirstAid', 3, 9)")
check("the bystander path refuses a non-doctor", lua.eval("#CLIENT") == 0 and lua.eval("said('error.not_ems')") is True)

print("\n--- the admins' revive command ---")
check("/medrevive is not registered", lua.eval("CMDS.medrevive") is None)

print("\n%d check(s) failed" % len(fails))
for f in fails: print("  ! " + f)
sys.exit(1 if fails else 0)
