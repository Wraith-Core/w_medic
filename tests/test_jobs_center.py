"""The jobs centre (server/main.lua): who may hire, promote and dismiss doctors, and what it writes."""
import locale, os, re, sys
locale.setlocale(locale.LC_ALL, "C")
from lupa.lua54 import LuaRuntime
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"F:\Server RedM\MajestyRP\FILSE\resources\[wraith]\w_medic"
def src(*p): return re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, *p), encoding="utf-8-sig").read())
# the raw text: this block has SQL with `backticks` inside strings and no CfxLua hash literals
MAIN = open(os.path.join(ROOT, "server", "main.lua"), encoding="utf-8-sig").read()
BLOCK = MAIN[MAIN.index("-- ── the doctor's job label follows his grade"):MAIN.index("-- Exports for the admin console")]

fails = []
def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok: fails.append(label)

def world():
    lua = LuaRuntime()
    lua.execute(r"""
    local function stub(name)
      return setmetatable({}, { __call = function() return stub(name .. '()') end,
                                __index = function(_, k) return stub(name .. '.' .. k) end })
    end
    setmetatable(_G, { __index = function(_, k) return stub(k) end })
    function vector3(x, y, z) return { x = x, y = y, z = z } end
    function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    """)
    lua.execute(src("config.lua"))
    lua.execute(r"""
    setmetatable(_G, nil)
    local V = {} V.__index = V
    V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
    V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
    DESK = Config.MDTDesk.coords
    -- server id -> character in the game
    P = {
      [1] = { char = 101, job = 'doctor', grade = 6, label = 'x', first = 'Min', last = 'Ister', at = 'desk' },
      [2] = { char = 102, job = 'doctor', grade = 5, label = 'x', first = 'Dep', last = 'Uty', at = 'desk' },
      [3] = { char = 103, job = 'doctor', grade = 3, label = 'x', first = 'Doc', last = 'Tor', at = 'desk' },
      [4] = { char = 104, job = 'unemployed', grade = 0, label = 'x', first = 'New', last = 'Guy', at = 'far' },
      [5] = { char = 105, job = 'police', grade = 9, label = 'x', first = 'Ad', last = 'Min', at = 'desk', admin = true },
    }
    DB = { -- characters not in the game
      [201] = { identifier = 'steam:a', job = 'doctor', jobgrade = 2, firstname = 'Off', lastname = 'Line' },
      [202] = { identifier = 'steam:b', job = 'doctor', jobgrade = 6, firstname = 'Old', lastname = 'Boss' },
    }
    CB, EVENTS, NOTES, OFFLINE, STATES, TIMERS = {}, {}, {}, {}, {}, {}
    function GetPlayers() local t = {} for id in pairs(P) do t[#t + 1] = tostring(id) end return t end
    function GetPlayerName(s) return P[tonumber(s)] and ('p' .. s) or nil end
    function GetPlayerPed(s) return tonumber(s) end
    function GetEntityCoords(ped) local p = P[ped] if p.at == 'desk' then return vector3(DESK.x + 1, DESK.y, DESK.z) end return vector3(0, 0, 0) end
    function GetResourceState(n) return n == 'vorp_core' and 'started' or 'missing' end
    function TriggerEvent(name, ...) EVENTS[#EVENTS + 1] = { name, ... } end
    function SetTimeout(_, f) TIMERS[#TIMERS + 1] = f end
    HANDLERS = {}
    function AddEventHandler(n, f) HANDLERS[n] = f end
    function CreateThread() end
    function Wait() end
    function print() end
    function Player(s) STATES[s] = STATES[s] or {} local st = STATES[s]
      return { state = setmetatable({ set = function(self, k, v) st[k] = v end }, { __index = st }) } end
    w = { callback = { register = function(n, f) CB[n] = f end }, notify = function(s, d) NOTES[#NOTES + 1] = { s, d.description } end }
    local function p(s) return P[tonumber(s)] end
    local fw = {
      FwGetCharacterIdentifier = function(_, s) return p(s) and p(s).char end,
      FwGetJob = function(_, s) return p(s) and p(s).job end,
      FwGetJobGrade = function(_, s) return p(s) and p(s).grade end,
      FwGetJobLabel = function(_, s) return p(s) and p(s).label end,
      FwGetFirstName = function(_, s) return p(s).first end,
      FwGetLastName = function(_, s) return p(s).last end,
      FwSetJob = function(_, s, j, g) p(s).job, p(s).grade = j, g return true end,
      FwSetJobLabel = function(_, s, l) p(s).label = l return true end,
      FwSetPlayerJobOffline = function(_, ident, cid, j, g, l) OFFLINE[#OFFLINE + 1] = { 'set', cid, j, g, l } DB[cid].job, DB[cid].jobgrade = j, g return true end,
      FwRemoveJobOffline = function(_, cid) OFFLINE[#OFFLINE + 1] = { 'remove', cid } DB[cid].job = 'unemployed' return true end,
      IsAdmin = function(_, s) return p(s) and p(s).admin == true end,
    }
    exports = { w_lib = setmetatable({}, { __index = function(_, k) return fw[k] end }) }
    MySQL = {
      query = { await = function() local t = {} for cid, r in pairs(DB) do if r.job == 'doctor' then t[#t + 1] = { charidentifier = cid, firstname = r.firstname, lastname = r.lastname, jobgrade = r.jobgrade } end end return t end },
      single = { await = function(_, a) return DB[a[1]] end },
    }
    function call(name, s, ...) return CB[name](s, ...) end
    """)
    lua.execute(BLOCK)
    return lua, lua.globals()

lua, g = world()
print("\n--- who may open it ---")
check("a plain doctor (grade 3) may not", lua.eval("call('w_medic:jobs:list', 3).error") == "no_access")
check("a civilian may not", lua.eval("call('w_medic:jobs:list', 4).error") == "no_access")
lua.execute("P[1].at = 'far'")
check("the minister away from the desk may not (it is a place, as in GW)", lua.eval("call('w_medic:jobs:list', 1).error") == "too_far")
lua.execute("P[1].at = 'desk'")
res = lua.eval("call('w_medic:jobs:list', 1)")
check("the minister at the desk opens it", res.ok is True)
gives = {r.grade: r.give for r in res.ranks.values()}
check("he gives every rank below his own, not his own", gives == {6: False, 5: True, 3: True, 2: True, 1: True, 0: True}, str(gives))
names = [d.name for d in res.doctors.values()]
check("every doctor is listed, in the game or not", set(names) == {"Min Ister", "Dep Uty", "Doc Tor", "Off Line", "Old Boss"}, str(names))
mine = [d for d in res.doctors.values() if d.charId == 101][0]
check("his own row cannot be touched", mine.touch is False)
check("the admin opens it too (no doctor rank needed)", lua.eval("call('w_medic:jobs:list', 5).ok") is True)

print("\n--- hiring ---")
check("the deputy cannot hire a deputy (his own rank)", lua.eval("call('w_medic:jobs:hire', 2, 4, 5).error") == "rank_too_high")
r = lua.eval("call('w_medic:jobs:hire', 2, 4, 3)")
check("the deputy hires a player as 'دكتور' (3)", r.ok is True and lua.eval("P[4].job") == "doctor" and lua.eval("P[4].grade") == 3)
check("with the rank's own label", lua.eval("P[4].label") == "دكتور", lua.eval("P[4].label"))
check("VORP's change events are announced (label rule, duty, client, logs)",
      any(e[1] == "vorp:playerJobChange" for e in lua.eval("EVENTS").values()))
check("the new doctor is told", any(n[1] == 4 and n[2] == "jobs.you_hired" for n in lua.eval("NOTES").values()))
check("hiring a doctor again is refused (change his rank instead)", lua.eval("call('w_medic:jobs:hire', 1, 4, 2).error") == "already_doctor")
check("nobody hires himself", lua.eval("call('w_medic:jobs:hire', 5, 5, 6).error") == "self")
check("an unknown server id is refused", lua.eval("call('w_medic:jobs:hire', 1, 99, 0).error") == "no_player")

print("\n--- ranks and dismissals ---")
check("the deputy cannot touch the minister", lua.eval("call('w_medic:jobs:setRank', 2, 101, 3).error") == "target_too_high")
check("nor change his own rank", lua.eval("call('w_medic:jobs:setRank', 2, 102, 3).error") == "self")
r = lua.eval("call('w_medic:jobs:setRank', 2, 103, 1)")
check("the deputy demotes a doctor in the game", r.ok is True and lua.eval("P[3].grade") == 1)
r = lua.eval("call('w_medic:jobs:setRank', 1, 201, 3)")
check("a doctor not in the game is changed on his saved character", r.ok is True and lua.eval("OFFLINE[1][1]") == "set" and lua.eval("OFFLINE[1][4]") == 3)
check("the minister cannot touch another minister (offline)", lua.eval("call('w_medic:jobs:setRank', 1, 202, 3).error") == "target_too_high")
r = lua.eval("call('w_medic:jobs:fire', 1, 103)")
check("dismissed in the game: unemployed", r.ok is True and lua.eval("P[3].job") == "unemployed")
check("the dismissed doctor is told", any(n[1] == 3 and n[2] == "jobs.you_fired" for n in lua.eval("NOTES").values()))
check("dismissing a non-doctor is refused", lua.eval("call('w_medic:jobs:fire', 1, 103).error") == "not_doctor")
r = lua.eval("call('w_medic:jobs:fire', 5, 202)")
check("the admin dismisses a minister (offline)", r.ok is True and lua.eval("OFFLINE[#OFFLINE][1]") == "remove")

print("\n--- the admin appoints the head, the head runs the doctors ---")
lua, g = world()
res = lua.eval("call('w_medic:jobs:list', 5)")
gives = {r.grade: r.give for r in res.ranks.values()}
check("the admin may give the head's rank only", gives == {6: True, 5: False, 3: False, 2: False, 1: False, 0: False}, str(gives))
check("the admin cannot hire a plain doctor", lua.eval("call('w_medic:jobs:hire', 5, 4, 3).error") == "rank_too_high")
r = lua.eval("call('w_medic:jobs:hire', 5, 4, 6)")
check("the admin hires a player as the head", r.ok is True and lua.eval("P[4].grade") == 6)
check("the admin cannot demote a doctor", lua.eval("call('w_medic:jobs:setRank', 5, 103, 2).error") == "admin_head_only")
r = lua.eval("call('w_medic:jobs:setRank', 5, 103, 6)")
check("the admin promotes a doctor to head", r.ok is True and lua.eval("P[3].grade") == 6)
check("the admin cannot dismiss a plain doctor", lua.eval("call('w_medic:jobs:fire', 5, 201).error") == "admin_head_only")
row = [d for d in lua.eval("call('w_medic:jobs:list', 5)").doctors.values() if d.charId == 201][0]
check("in the admin's list a plain doctor offers only 'make him head', no dismissal",
      list(row.ranks.values()) == [6] and row.fire is False, "%s fire=%s" % (list(row.ranks.values()), row.fire))
row = [d for d in lua.eval("call('w_medic:jobs:list', 1)").doctors.values() if d.charId == 201][0]
check("in the head's list the same doctor gets every rank below the head, and dismissal",
      sorted(row.ranks.values()) == [0, 1, 3, 5] and row.fire is True, "%s fire=%s" % (sorted(row.ranks.values()), row.fire))

print("\n--- the key on the desk ---")
lua, g = world()
def flag(sid):
    lua.execute("HANDLERS['vorp:SelectedCharacter'](%d) for _, f in ipairs(TIMERS) do f() end TIMERS = {}" % sid)
    return lua.eval("STATES[%d] and STATES[%d]['w_medic:jobsCenter']" % (sid, sid))
check("the minister sees the key", flag(1) is True)
check("the deputy sees the key", flag(2) is True)
check("the admin sees the key", flag(5) is True)
check("a plain doctor does not", flag(3) is False)
check("a civilian does not", flag(4) is False)
lua.execute("call('w_medic:jobs:setRank', 1, 102, 3) HANDLERS['vorp:playerJobGradeChange'](2) for _, f in ipairs(TIMERS) do f() end TIMERS = {}")
check("demoted, the deputy loses the key", lua.eval("STATES[2]['w_medic:jobsCenter']") is False)

print("\n%d check(s) failed" % len(fails))
for f in fails: print("  ! " + f)
sys.exit(1 if fails else 0)
