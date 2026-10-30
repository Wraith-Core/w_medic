import unittest
from pathlib import Path

def run_checks():
    from pathlib import Path
    """A doctor's job label follows his grade (current contiguous doctor ranks), whatever /setjob or /jobs typed."""
    import locale, os, re, sys
    locale.setlocale(locale.LC_ALL, "C")
    from lupa.lua54 import LuaRuntime
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    
    ROOT = str(Path(__file__).resolve().parents[1])
    def src(*p): return re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, *p), encoding="utf-8-sig").read())
    # the raw text: this part has SQL with `backticks` inside strings and no CfxLua hash literals
    MAIN = open(os.path.join(ROOT, "server", "main.lua"), encoding="utf-8-sig").read()
    BLOCK = MAIN[MAIN.index("-- ── the doctor's job label follows his grade"):MAIN.index("-- Exports for the admin console")]
    
    fails = []
    def check(label, ok, detail=""):
        print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
        if not ok: fails.append(label)
    
    lua = LuaRuntime()
    # the real config, every engine/library global stubbed
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
    CHARS = {
      [1] = { job = 'doctor', grade = 3, label = 'الـمـارشـال' },
      [2] = { job = 'doctor', grade = 1, label = 'طـبـيـب مـتـدرب ' },
      [3] = { job = 'police', grade = 3, label = 'الـمـارشـال' },
      [4] = { job = 'doctor', grade = 4, label = 'كيفي' },
    }
    SETS, TIMERS, HANDLERS, THREADS = {}, {}, {}, {}
    function GetPlayerName(s) return CHARS[tonumber(s)] and 'p' or nil end
    function GetPlayers() return { '1', '2', '3', '4' } end
    function SetTimeout(ms, fn) TIMERS[#TIMERS + 1] = fn end
    function flush() local t = TIMERS TIMERS = {} for _, f in ipairs(t) do f() end end
    function AddEventHandler(n, f) HANDLERS[n] = f end
    function CreateThread(f) THREADS[#THREADS + 1] = f end
    function Wait() end
    exports = { w_lib = {
      FwGetJob = function(_, s) return CHARS[s].job end,
      FwGetJobGrade = function(_, s) return CHARS[s].grade end,
      FwGetJobLabel = function(_, s) return CHARS[s].label end,
      FwSetJobLabel = function(_, s, l) CHARS[s].label = l SETS[#SETS + 1] = s return true end,
      FwGetCharacterIdentifier = function(_, s) return 100 + s end,
      IsAdmin = function() return false end,
    } }
    -- the jobs centre that shares this part of server/main.lua
    w = { callback = { register = function() end }, notify = function() end }
    function Player() return { state = setmetatable({ set = function() end }, { __index = function() return nil end }) } end
    function GetResourceState() return 'missing' end
    function print() end
    """)
    lua.execute(BLOCK)
    lua.execute("for _, f in ipairs(THREADS) do f() end")  # the start-up pass over the players online
    
    ranks = lua.eval("Config.DoctorRanks")
    check("w_medic's ranks are gw-medic's (0,1,2,3,4,5)", sorted(ranks.keys()) == [0, 1, 2, 3, 4, 5], str(sorted(ranks.keys())))
    check("a grade 3 doctor called 'المارشال' becomes 'دكتور'", lua.eval("CHARS[1].label") == "دكتور", lua.eval("CHARS[1].label"))
    check("a grade 1 doctor with grade 0's name becomes 'طـبـيـب مـتـمـرس'", lua.eval("CHARS[2].label") == "طـبـيـب مـتـمـرس", lua.eval("CHARS[2].label"))
    check("a policeman is never touched", lua.eval("CHARS[3].label") == "الـمـارشـال")
    check("grade 4 is the deputy's rank", lua.eval("CHARS[4].label") == "نائب وزير الصحة")
    
    # a promotion: VORP fires the event BEFORE it stores the new grade
    lua.execute("SETS = {} HANDLERS['vorp:playerJobGradeChange'](1, 5, 3) CHARS[1].grade = 5")
    check("nothing is written inside the event (the grade is still the old one)", lua.eval("#SETS") == 0)
    lua.execute("flush()")
    check("a moment later the label is the minister's", lua.eval("CHARS[1].label") == "وزيـر الـصـحـة", lua.eval("CHARS[1].label"))
    
    # /jobs: setJob, setJobGrade, then setJobLabel with the role's own (padded) label
    lua.execute("SETS = {} HANDLERS['vorp:playerJobChange'](3, 'doctor', 'police') CHARS[3].job = 'doctor' CHARS[3].grade = 4 CHARS[3].label = '  نائب وزير الصحه ' flush()")
    check("a new doctor from /jobs gets the clean rank name", lua.eval("CHARS[3].label") == "نائب وزير الصحة", lua.eval("CHARS[3].label"))
    lua.execute("SETS = {} HANDLERS['vorp:SelectedCharacter'](1) flush()")
    check("a label already right is not rewritten", lua.eval("#SETS") == 0)
    
    print("\n%d check(s) failed" % len(fails))
    for f in fails: print("  ! " + f)
    if fails: raise AssertionError('Failed checks: ' + ', '.join(fails))

class LegacyChecks(unittest.TestCase):
    def test_current_resource(self): run_checks()

if __name__ == '__main__': unittest.main()
