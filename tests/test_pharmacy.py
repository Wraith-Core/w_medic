"""Behaves the shipped pharmacy code, not a copy of it.

The region under test is sliced straight out of server/main.lua between its two
markers, so the test runs the lines the server runs.
"""
import sys

from lupa.lua54 import LuaRuntime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_ambulancejob\server\main.lua"

BEGIN = "-- ── the pharmacy cabinet"
END = "-- The bed each player occupies"

source = open(SRC, encoding="utf-8-sig").read()
PHARMACY = source[source.index(BEGIN):source.index(END)]
# the functions under test are file-locals; hand them out so the test can call them
PHARMACY += "\n__test = { setupPharmacy = setupPharmacy, takeSupplies = takeSupplies, activeBag = activeBag }\n"
print("extracted %d lines from server/main.lua" % PHARMACY.count("\n"))


def build(bag, started=None):
    # In a real server exactly ONE bag is started. Marking them all would make the bridge's own
    # fallback loop pick w_inventory every time, which is not what any deployment looks like.
    started = (bag,) if started is None else started
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    log = {"shops": [], "given": [], "notified": [], "prints": [], "states": {}}

    # lupa's table_from({k, v}) builds an ARRAY; these are dicts, so build them explicitly.
    def T(**kw):
        t = lua.table()
        for k, v in kw.items():
            t[k] = v
        return t

    def A(*items):
        t = lua.table()
        for i, v in enumerate(items, 1):
            t[i] = v
        return t

    g.Config = T(
        Pharmacy=T(
            enabled=True, shopId="hospital_pharmacy", groups=A("ambulance"),
            restockMinutes=60, stock=T(bandage=3, painkillers=2, firstaid=1),
            windowMinutes=60, maxPerWindow=2, maxPerVisit=2,
            perVisit=T(bandage=1, painkillers=1, firstaid=1),
        ),
        Items=T(label="info.safe", items=A(
            T(name="bandage", price=0, amount=3, info={}),
            T(name="painkillers", price=0, amount=2, info={}),
            T(name="firstaid", price=0, amount=1, info={}),
        )),
    )

    g.GetResourceState = lambda name: "started" if name in started else "missing"
    g.print = lambda *a: log["prints"].append(" ".join(str(x) for x in a))

    players = {}

    def get_player(src, *rest):
        p = players.get(src)
        return T(PlayerData=T(job=T(name=p["job"], onduty=p["onduty"]))) if p else None

    def set_player(src, job="ambulance", onduty=True):
        players[src] = {"job": job, "onduty": onduty}

    g.setPlayer = set_player
    g.WCore = T(Functions=T(GetPlayer=get_player))

    def inv_add(*args):
        # exports.X:Method(src, item, count, meta) -- the leading table is `self` and the
        # trailing one is the metadata the resource passes, so the payload is args[-4:].
        src, item, count = args[-4], args[-3], args[-2]
        log["given"].append((src, item, count))
        return True

    def inv_carry(*args):
        src, item, count = args[-3], args[-2], args[-1]
        return log["states"].get("carry", {}).get(item, 99) >= count

    g.exports = T(w_lib=T(
        InvName=lambda *_: bag,
        InvCanCarry=inv_carry,
        InvAddItem=inv_add,
    ))

    def register_shop(*args):
        log["shops"].append((args[-2], args[-1]))
        return True

    g.exports["w_inventory"] = T(RegisterShop=register_shop)

    g.TriggerClientEvent = lambda ev, tgt, *a: log["notified"].append((ev, tgt, a))
    g.Wait = lambda ms: log["states"].update(waited=log["states"].get("waited", 0) + ms)
    g.GetGameTimer = lambda: log["states"].get("now", 0)
    # CreateThread is CALLED, not indexed: __call was removed in Lua 5.4, so it must be a function.
    g.CreateThread = lambda fn: log["states"].setdefault("thread", fn)

    g.callbacks = lua.table()

    def cb_register(name, fn):
        g.callbacks[name] = fn

    g.w = T(callback=T(register=cb_register))

    log["handlers"] = {}

    def add_event_handler(name, fn):
        log["handlers"].setdefault(name, []).append(fn)

    g.AddEventHandler = add_event_handler

    lua.execute(PHARMACY)
    ok, mode = lua.globals().__test.setupPharmacy()
    log["setup"] = (ok, mode)
    return lua, g, log


fails = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok:
        fails.append(label)


def take(g, src):
    g.callbacks["w_ambulancejob:takeSupplies"](src)


print("\n--- the cabinet is created on every bag, in the right shape ---")
for bag, expect_shop in (("w_inventory", True), ("vorp_inventory", False),
                         ("rsg-inventory", False), ("qbr-inventory", False)):
    lua, g, log = build(bag)
    check("%-14s -> %s" % (bag, "a registered shop" if expect_shop else "the handout"),
          (len(log["shops"]) == 1) == expect_shop,
          "setupPharmacy -> %s, shops=%d %s" % (log["setup"], len(log["shops"]), log["prints"]))

print("\n--- the shop that is registered carries the shelf and the group ---")
lua, g, log = build("w_inventory")
if log["shops"]:
    sid, details = log["shops"][0]
    inv = details["inventory"]
    counts = {inv[i]["name"]: inv[i]["count"] for i in range(1, len(inv) + 1)}
    check("shop id is the configured one", sid == "hospital_pharmacy", str(sid))
    check("stock comes from Config.Pharmacy.stock",
          counts == {"bandage": 3, "painkillers": 2, "firstaid": 1}, str(counts))
    check("the job group is handed to the bag",
          [details["groups"][i] for i in range(1, len(details["groups"]) + 1)] == ["ambulance"],
          str([details["groups"][i] for i in range(1, len(details["groups"]) + 1)]))

print("\n--- the handout refuses what the client cannot be trusted about ---")
lua, g, log = build("vorp_inventory")
g.setPlayer(1, job="unemployed")
take(g, 1)
check("a civilian is refused", len(log["given"]) == 0)

lua, g, log = build("vorp_inventory")
g.setPlayer(2, job="ambulance", onduty=False)
take(g, 2)
check("an off-duty medic is refused", len(log["given"]) == 0)

lua, g, log = build("vorp_inventory")
g.setPlayer(3)
log["states"]["carry"] = {"bandage": 0, "painkillers": 0, "firstaid": 0}
take(g, 3)
check("a full bag is given nothing", len(log["given"]) == 0)

print("\n--- the handout serves a medic, within the window ---")
lua, g, log = build("vorp_inventory")
g.setPlayer(4)
take(g, 4)
first = len(log["given"])
check("an on-duty medic is served", first > 0, "%d item(s)" % first)
check("and is told what arrived",
      any(n[0] == "hospital:client:PharmacyHandout" for n in log["notified"]))

lua, g, log = build("vorp_inventory")
g.setPlayer(5)
for _ in range(4):
    take(g, 5)
check("maxPerWindow = 2 caps the visits", len(log["given"]) <= 2 * first,
      "%d item(s) after four presses (one visit = %d)" % (len(log["given"]), first))

print("\n--- the shelf is shared, not per medic ---")
lua, g, log = build("vorp_inventory")
for src in range(7, 13):
    g.setPlayer(src)
    take(g, src)
tally = {}
for _s, item, n in log["given"]:
    tally[item] = tally.get(item, 0) + int(n)
check("the whole shelf is finite (3+2+1 across six medics)",
      sum(tally.values()) <= 6, str(tally))

print("\n--- the window allows exactly maxPerWindow visits ---")
lua, g, log = build("vorp_inventory")
g.setPlayer(13)
take(g, 13)
after1 = len(log["given"])
take(g, 13)
after2 = len(log["given"])
take(g, 13)
after3 = len(log["given"])
check("the first two visits are served", after1 > 0 and after2 > after1,
      "%d -> %d" % (after1, after2))
check("the third is refused inside the window", after3 == after2,
      "%d -> %d" % (after2, after3))
check("there is a playerDropped handler to call",
      len(log["handlers"].get("playerDropped", [])) == 1)
# the handler reads the GLOBAL `source`, exactly as FiveM sets it for an event
g.source = 13
for fn in log["handlers"]["playerDropped"]:
    fn()
log["given"].clear()
take(g, 13)
check("after dropping he is served again (a fresh window)", len(log["given"]) > 0,
      "%d item(s)" % len(log["given"]))

print("\n%d check(s) failed" % len(fails))
for f in fails:
    print("  ! " + f)
sys.exit(1 if fails else 0)