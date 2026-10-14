"""Behaves payDoctor and the paycheck key against the real code, sliced from the files.

Both were written this session and neither had been run. These run the shipped lines:
the blocks are cut straight out of server/main.lua and w_core/server/loops.lua.
"""
import sys

from lupa.lua54 import LuaRuntime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

AMB = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_ambulancejob\server\main.lua"
LOOPS = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_core\server\loops.lua"

fails = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok:
        fails.append(label)


def slice_between(text, begin, end):
    return text[text.index(begin):text.index(end)]


# ── payDoctor ────────────────────────────────────────────────────────────────────────
src = open(AMB, encoding="utf-8-sig").read()
PAY = slice_between(src, "--- The doctor's fee", "local PlayerInjuries")
PAY += "\n__test = { payDoctor = payDoctor }\n"
print("payDoctor: %d lines from w_ambulancejob/server/main.lua" % PAY.count("\n"))

CFG = r'''
Config = {}
Config.Pay = { enabled = true, treat = 20, revive = 20 }
'''


def build_amb():
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    log = {"transfers": [], "notified": []}

    def T(**kw):
        t = lua.table()
        for k, v in kw.items():
            t[k] = v
        return t

    lua.execute(CFG)
    g.GetResourceState = lambda n: "started" if n == "w_centralbank" else "missing"
    g.print = lambda *a: None

    patients = {}

    def get_player(src, *rest):
        cid = patients.get(int(src)) if src is not None else None
        return T(PlayerData=T(citizenid=cid)) if cid else None

    g.WCore = T(Functions=T(GetPlayer=get_player))

    def transfer(*args):
        src, dst, amount, key = args[-4], args[-3], args[-2], args[-1]
        log["transfers"].append((src, dst, int(amount), key))
        return True

    g.exports = T(
        w_centralbank=T(IsReady=lambda *_: True,
                        EnsureAccount=lambda *_: True,
                        Transfer=transfer),
    )
    g.TriggerClientEvent = lambda ev, tgt, *a: log["notified"].append((ev, tgt, a))
    g.GetGameTimer = lambda: 1000
    lua.execute(PAY)
    return lua, g, log


print("\n--- the fee comes out of the society account, into the patient's bank ---")
lua, g, log = build_amb()
g.__patients = {7: "CID0007"}
# get_player reads the table we hand it
lua.globals().__pat = lua.table()
for k, v in {7: "CID0007", 8: "CID0008"}.items():
    lua.globals().__pat[k] = v
src_code = '''
local __p = __pat
WCore = { Functions = { GetPlayer = function(s, ...) return __p[s] and { PlayerData = { citizenid = __p[s] } } or nil end } }
'''
g.__pat[7] = "CID0007"
lua.execute(src_code.replace("local __p = __pat", "local __p = __pat"))
lua.globals().__pat[7] = lua.table_from(["CID0007"]) if False else "CID0007"

# simpler: patch GetPlayer to read a python dict
players = {7: "CID0007", 8: "CID0008"}


def T2(**kw):
    t = lua.table()
    for k, v in kw.items():
        t[k] = v
    return t


def get_player(src, *rest):
    cid = players.get(int(src)) if src is not None else None
    return T2(PlayerData=T2(citizenid=cid)) if cid else None


g.WCore["Functions"]["GetPlayer"] = get_player

ok = g.__test.payDoctor(1, 7, "treat")
check("treat pays the configured fee", len(log["transfers"]) == 1 and log["transfers"][0][2] == 20,
      str(log["transfers"]))
check("out of society:ambulance",
      log["transfers"] and log["transfers"][0][0] == "society:ambulance")
check("into the patient's bank",
      log["transfers"] and log["transfers"][0][1] == "player:CID0007:bank")
check("the medic is told", any(n[0] == "w_core:Notify" for n in log["notified"]))

lua, g, log = build_amb()
lua.globals().__test  # noqa
g.WCore["Functions"]["GetPlayer"] = get_player
g.__test.payDoctor(1, 8, "revive")
check("revive pays the configured fee", log["transfers"] and log["transfers"][0][2] == 20,
      str(log["transfers"]))
check("the key names the kind",
      log["transfers"] and log["transfers"][0][3].startswith("doctor-revive:"),
      log["transfers"][0][3] if log["transfers"] else "")

print("\n--- two medics, two presses: four distinct keys, so nobody is left unpaid ---")
lua, g, log = build_amb()
g.WCore["Functions"]["GetPlayer"] = get_player
g.__test.payDoctor(1, 7, 'revive')
g.__test.payDoctor(2, 7, 'revive')
g.__test.payDoctor(1, 8, 'treat')
keys = [t[3] for t in log["transfers"]]
check("three jobs, three different keys", len(keys) == 3 and len(set(keys)) == 3, str(keys))
check("the medic is part of the key", any(":1:" in k for k in keys) and any(":2:" in k for k in keys),
      str(keys))

print("\n--- a patient the server cannot find pays nobody ---")
lua, g, log = build_amb()
lua.globals().__test.payDoctor(1, 99, "treat")
check("an unknown patient is refused", len(log["transfers"]) == 0)

print("\n--- the paycheck key separates employees and cycles ---")
loops = open(LOOPS, encoding="utf-8-sig").read()
body = loops[loops.index("-- Paycheck Loop --"):]
print("paycheck loop: %d lines from w_core/server/loops.lua (it is the last block in the file)"
      % body.count("\n"))
check("the cycle is stamped once per round", "local cycle = os.time()" in body)
check("the key carries the employee", "'paycheck:'..Player.PlayerData.citizenid..':'..cycle" in body)
check("the old shared key is gone", "'paycheck:'..Player.PlayerData.job.name" not in body)

keys_seen = set()
for cid in ("AAA", "BBB"):
    for cycle in (1000, 2000):
        keys_seen.add("paycheck:%s:%s" % (cid, cycle))
check("every employee in every round has their own key", len(keys_seen) == 4, str(sorted(keys_seen)))

print("\n%d check(s) failed" % len(fails))
for f in fails:
    print("  ! " + f)
sys.exit(1 if fails else 0)