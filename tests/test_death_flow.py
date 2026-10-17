"""client/dead.lua + client/laststand.lua on a simulated clock: a death, the last stand, bleeding
out, the respawn key, and a revive from outside (VORP's /revive, a txAdmin heal)."""
import locale, os, re, sys
locale.setlocale(locale.LC_ALL, "C")
from lupa.lua54 import LuaRuntime
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"F:\Server RedM\MajestyRP\FILSE\resources\[wraith]\w_medic"
def src(*p): return re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, *p), encoding="utf-8-sig").read())

fails = []
def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok: fails.append(label)

WORLD = r"""
-- the clock and the threads (Wait yields; step() runs everything due)
NOW, THREADS = 0, {}
function GetGameTimer() return NOW end
function CreateThread(fn) THREADS[#THREADS + 1] = { co = coroutine.create(fn), wake = NOW } end
function Wait(ms) coroutine.yield(ms or 0) end
function step(ms)
  local target = NOW + ms
  while true do
    local best
    for _, t in ipairs(THREADS) do
      if not t.dead and t.wake <= target and (not best or t.wake < best.wake) then best = t end
    end
    if not best then break end
    if best.wake > NOW then NOW = best.wake end
    local ok, r = coroutine.resume(best.co)
    if not ok then error(r) end
    if coroutine.status(best.co) == 'dead' then best.dead = true else best.wake = NOW + math.max(r or 0, 1) end
  end
  NOW = target
end

-- the ped
PED_DEAD = false
function PlayerId() return 0 end
function PlayerPedId() return 7 end
function NetworkIsPlayerActive() return true end
function IsEntityDead() return PED_DEAD end
function SetEntityHealth(_, h) if h == 0 then PED_DEAD = true end end
function DoesEntityExist() return true end
function GetEntitySpeed() return 0.0 end
function IsPedRagdoll() return false end
function SetEntityInvincible() end
function DisableAllControlActions() end
function EnableControlAction() end
function SetCurrentPedWeapon() end
function NetworkGetEntityKillerOfPlayer() return 0, 0 end
function GetPedSourceOfDeath() return 0 end
function NetworkGetPlayerIndexFromPed() return -1 end
function GetPlayerName() return 'me' end
function GetPlayerServerId() return 1 end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end

-- what the scripts tell the server
SENT = {}
function TriggerServerEvent(name, ...) SENT[#SENT + 1] = { name = name, a = ... } end
function TriggerEvent(name) SENT[#SENT + 1] = { name = 'local:' .. name } end
function count(name) local n = 0 for _, s in ipairs(SENT) do if s.name == name then n = n + 1 end end return n end
function last(name) for i = #SENT, 1, -1 do if SENT[i].name == name then return SENT[i].a end end end
HANDLERS = {}
function RegisterNetEvent(name, fn) if fn then HANDLERS[name] = fn end end
function AddEventHandler(name, fn) HANDLERS[name] = fn end
function locale(k) return k end
function GetCurrentResourceName() return 'w_medic' end

-- the prompt group of the death screen
GROUP = { visible = {}, enabled = {} }
w = { prompt = { createGroup = function()
  local g = { id = 'grp' }
  function g.addPrompt() end function g.display() GROUP.shown = true end function g.hide() GROUP.shown = false end
  function g.delete() GROUP.deleted = true end function g.setTitle(t) GROUP.title = t end
  function g.setVisible(k, v) GROUP.visible[k] = v end function g.setEnabled(k, v) GROUP.enabled[k] = v end
  function g.setLabel() end function g.isVisible() return GROUP.shown end
  return g end }, getClosestPlayer = function() return nil end, notify = function() end }
WCore = { Functions = { Notify = function() end }, Shared = { GetWeapon = function() return nil end } }

Config = { TimeTillRespawn = 300, MinimumRevive = 180, DeathTime = 300, BillCost = 25 }
isDead, isReviving, isInHospitalBed = false, false, false
"""

def world():
    lua = LuaRuntime()
    lua.execute(WORLD)
    lua.execute(src("client", "laststand.lua"))
    lua.execute(src("client", "dead.lua"))
    return lua, lua.globals()

print("\n--- a death becomes a last stand, and stays one ---")
lua, g = world()
lua.execute("step(2000)")
check("alive: nothing happens", g.InLaststand is False and g.isDead is False)
lua.execute("PED_DEAD = true step(2000)")
check("the dead ped starts the last stand", g.InLaststand is True, "InLaststand=%s isDead=%s" % (g.InLaststand, g.isDead))
check("the countdown starts full", 295 <= g.LaststandTime <= 300, str(g.LaststandTime))
check("the doctors are alerted once", lua.eval("count('hospital:server:ambulanceAlert')") == 1)
check("the server knows him in last stand", lua.eval("last('hospital:server:SetLaststandStatus')") is True)
lua.execute("step(60000)")
check("a minute later he is STILL in last stand (it used to turn into death after 1 s)",
      g.InLaststand is True and g.isDead is False, "InLaststand=%s isDead=%s" % (g.InLaststand, g.isDead))
check("no alert storm", lua.eval("count('hospital:server:ambulanceAlert')") == 1, str(lua.eval("count('hospital:server:ambulanceAlert')")))
check("the countdown runs", 235 <= g.LaststandTime <= 241, str(g.LaststandTime))
check("both keys show from the first second (as under GW)", lua.eval("GROUP.visible.G") is True and lua.eval("GROUP.visible.J") is True)
check("J is locked while he bleeds out", lua.eval("GROUP.enabled.J") is False)
check("G is locked above MinimumRevive (180 in this run)", lua.eval("GROUP.enabled.G") is not True)
lua.execute("step(65000)")
check("once under MinimumRevive the G key is offered", lua.eval("GROUP.visible.G") is True and lua.eval("GROUP.enabled.G") is True)
lua.execute("HANDLERS['w_lib:promptCompleted']('grp', 'G')")
check("G calls a doctor", lua.eval("count('hospital:server:ambulanceAlert')") == 2)
lua.execute("HANDLERS['w_lib:promptCompleted']('grp', 'G')")
check("once", lua.eval("count('hospital:server:ambulanceAlert')") == 2)

print("\n--- bleeding out ---")
lua.execute("step(200000)")
check("after the countdown he is dead", g.isDead is True and g.InLaststand is False, "isDead=%s InLaststand=%s" % (g.isDead, g.InLaststand))
check("the server knows him dead", lua.eval("last('hospital:server:SetDeathStatus')") is True)
check("the respawn key is open at once (300 s already waited)", lua.eval("GROUP.enabled.J") is True)
alerts = lua.eval("count('hospital:server:ambulanceAlert')")
lua.execute("step(120000)")
check("dead, he does not fall back into last stand", g.InLaststand is False and g.isDead is True)
check("and the doctors are not paged again", lua.eval("count('hospital:server:ambulanceAlert')") == alerts)
lua.execute("HANDLERS['w_lib:promptCompleted']('grp', 'J')")
check("J sends him to the hospital", lua.eval("count('local:hospital:client:RespawnAtHospital')") == 1)
lua.execute("HANDLERS['w_lib:promptCompleted']('grp', 'J')")
check("once", lua.eval("count('local:hospital:client:RespawnAtHospital')") == 1)
lua.execute("HANDLERS['hospital:client:RespawnRefused']() HANDLERS['w_lib:promptCompleted']('grp', 'J')")
check("a refusal opens the key again", lua.eval("count('local:hospital:client:RespawnAtHospital')") == 2)

print("\n--- MinimumRevive = TimeTillRespawn (the live config): G at once ---")
lua, g = world()
lua.execute("Config.MinimumRevive = 300 Laststand.MinimumRevive = 300 PED_DEAD = true step(2000)")
check("G is usable from the first second", lua.eval("GROUP.visible.G") is True and lua.eval("GROUP.enabled.G") is True)
lua.execute("step(300000)")
check("dead and never called: G still calls a doctor", g.isDead is True and lua.eval("GROUP.enabled.G") is True)
before = lua.eval("count('hospital:server:ambulanceAlert')")
lua.execute("HANDLERS['w_lib:promptCompleted']('grp', 'G')")
check("G after death pages the doctors", lua.eval("count('hospital:server:ambulanceAlert')") == before + 1)
lua.execute("step(1000)")
check("then it is spent", lua.eval("GROUP.enabled.G") is False)

print("\n--- the live timings (read from config.lua) ---")
cfg = open(os.path.join(ROOT, "config.lua"), encoding="utf-8-sig").read()
ttr = int(re.search(r"^Config\.TimeTillRespawn\s*=\s*(\d+)", cfg, re.M).group(1))
mrv = int(re.search(r"^Config\.MinimumRevive\s*=\s*(\d+)", cfg, re.M).group(1))
check("G works from the first second (MinimumRevive >= TimeTillRespawn)", mrv >= ttr, "%d / %d" % (mrv, ttr))
lua, g = world()
lua.execute("Config.TimeTillRespawn = %d Config.MinimumRevive = %d Laststand.ReviveInterval = %d Laststand.MinimumRevive = %d" % (ttr, mrv, ttr, mrv))
lua.execute("PED_DEAD = true step(2000)")
check("J shows, locked, at the start", lua.eval("GROUP.visible.J") is True and lua.eval("GROUP.enabled.J") is False)
check("G is usable at once", lua.eval("GROUP.enabled.G") is True)
lua.execute("step(%d)" % ((ttr - 10) * 1000))
check("%d s in: J still locked" % (ttr - 8), lua.eval("GROUP.enabled.J") is False and g.InLaststand is True)
lua.execute("step(15000)")
check("after %d s: J opens (wake up at the doctor)" % ttr, g.isDead is True and lua.eval("GROUP.enabled.J") is True)

print("\n--- revived from outside (VORP's /revive, txAdmin) ---")
lua, g = world()
lua.execute("PED_DEAD = true step(3000)")
check("down", g.InLaststand is True)
lua.execute("PED_DEAD = false step(1000)")
check("a second up is no revive yet (a glitch is not trusted)", g.InLaststand is True)
lua.execute("step(4000)")
check("three seconds up: the downed state is dropped", g.InLaststand is False and g.isDead is False)
check("and the server is told", lua.eval("last('hospital:server:SetLaststandStatus')") is False
      and lua.eval("last('hospital:server:SetDeathStatus')") is False)
lua.execute("step(30000)")
check("no stray death afterwards", g.InLaststand is False and g.isDead is False)
lua.execute("PED_DEAD = true step(2000)")
check("and the next death is a fresh last stand", g.InLaststand is True and 295 <= g.LaststandTime <= 300, str(g.LaststandTime))

print("\n--- revived within the first second (maj_revive's point, an admin) ---")
lua, g = world()
lua.execute("PED_DEAD = true step(300)")
check("the watcher has seen the death", lua.eval("count('hospital:server:ambulanceAlert')") == 0)
lua.execute("PED_DEAD = false step(5000)")
check("alive again: he is NOT put back down (it used to kill him)", lua.eval("PED_DEAD") is False)
check("no last stand, no death", g.InLaststand is False and g.isDead is False)
check("no doctor paged, nothing told to the server", lua.eval("count('hospital:server:ambulanceAlert')") == 0
      and lua.eval("count('hospital:server:SetLaststandStatus')") == 0)

print("\n--- a hospital bed is not mistaken for a revive ---")
lua, g = world()
lua.execute("PED_DEAD = true step(3000) step(300000)")
check("dead", g.isDead is True)
lua.execute("isInHospitalBed = true PED_DEAD = false step(10000)")
check("alive in the bed, still in the hospital's hands", g.isDead is True)

print("\n%d check(s) failed" % len(fails))
for f in fails: print("  ! " + f)
sys.exit(1 if fails else 0)
