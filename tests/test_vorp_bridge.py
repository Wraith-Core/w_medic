import unittest
from pathlib import Path

def run_checks():
    from pathlib import Path
    """server/wcore_shim.lua and c/wcore_shim.lua, run for real against a fake VORP + w_lib."""
    import locale, os, re, sys
    locale.setlocale(locale.LC_ALL, "C")
    from lupa.lua54 import LuaRuntime
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    
    ROOT = str(Path(__file__).resolve().parents[1])
    def src(*p): return re.sub(r"`([^`]+)`", r'"\1"', open(os.path.join(ROOT, *p), encoding="utf-8-sig").read())
    SERVER, CLIENT = src("server", "wcore_shim.lua"), src("c", "wcore_shim.lua")
    
    fails = []
    def check(label, ok, detail=""):
        print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
        if not ok: fails.append(label)
    
    # ── the server side ─────────────────────────────────────────────────────────
    FAKE_SERVER = r"""
    LOG = { client = {}, commands = {} }
    NET, LOCAL, CALLBACKS, USABLE = {}, {}, {}, {}
    CHARS = {
      [1] = { charIdentifier = 101, identifier = 'steam:1', job = 'doctor',  jobGrade = 3, firstname = 'A', lastname = 'B', isdead = false },
      [2] = { charIdentifier = 102, identifier = 'steam:2', job = 'unemployed', jobGrade = 0, firstname = 'C', lastname = 'D', isdead = 1 },
    }
    ADMINS = { [3] = true }
    BAG = { [1] = { bandage = 2, syringe = 0 } }
    function GetResourceState(n) return (n == 'vorp_core' or n == 'w_lib') and 'started' or 'missing' end
    function GetPlayerName(s) s = tonumber(s) return (s == 1 or s == 2 or s == 3) and ('p' .. s) or nil end
    function GetPlayers() return { '1', '2', '3' } end
    function RegisterNetEvent(name, fn) if fn then NET[name] = fn end end
    function AddEventHandler(name, fn) LOCAL[name] = fn end
    function TriggerClientEvent(name, src, ...) LOG.client[#LOG.client + 1] = { name = name, src = src, args = table.pack(...) } end
    function RegisterCommand(name, fn) LOG.commands[name] = fn end
    function IsPlayerAceAllowed() return false end
    function print() end
    TIMERS = {}
    function SetTimeout(ms, fn) TIMERS[#TIMERS + 1] = fn end
    function flush() local t = TIMERS TIMERS = {} for _, f in ipairs(t) do f() end end
    local function char(src) return CHARS[tonumber(src)] end
    local fw = {
      FwGetCharacterIdentifier = function(_, s) local c = char(s) return c and c.charIdentifier end,
      FwGetJob = function(_, s) local c = char(s) return c and c.job or 'unemployed' end,
      FwGetJobGrade = function(_, s) local c = char(s) return c and c.jobGrade or 0 end,
      FwGetJobLabel = function(_, s) local c = char(s) return c and c.job end,
      FwGetIdentifier = function(_, s) local c = char(s) return c and c.identifier end,
      FwGetFirstName = function(_, s) local c = char(s) return c and c.firstname or '' end,
      FwGetLastName = function(_, s) local c = char(s) return c and c.lastname or '' end,
      FwClearInventory = function() return true end,
      IsAdmin = function(_, s) return ADMINS[s] == true end,
      InvRemoveItem = function(_, s, item, n) local b = BAG[s] or {} if (b[item] or 0) >= n then b[item] = b[item] - n return true end return false end,
      InvAddItem = function() return true end,
      InvGetItemCount = function(_, s, item) return (BAG[s] or {})[item] or 0 end,
      InvRegisterUsableItem = function(_, item, close, cb) USABLE[item] = cb return true end,
    }
    exports = {
      w_lib = setmetatable({}, { __index = function(_, k)
        local f = fw[k] if not f then error('No such export ' .. k .. ' in resource w_lib') end return f end }),
      vorp_core = { GetCore = function() return { getUser = function(s)
        local c = char(s) if not c then return nil end return { getUsedCharacter = c } end } end },
    }
    NOTICES = {}
    w = { notify = function(s, d) NOTICES[#NOTICES + 1] = { s, d.description } end,
          callback = { register = function(n, f) CALLBACKS[n] = f end } }
    SQL = {}
    MySQL = { single = { await = function(q, p) return p[1] == 102 and { charidentifier = 102, identifier = 'steam:2', firstname = 'C', lastname = 'D', job = 'unemployed', jobgrade = 0, isdead = 1 } or nil end },
              update = { await = function(q, p) SQL[#SQL + 1] = { q, p } return 1 end } }
    function fire(name, src, ...) source = src return NET[name](...) end
    function lastClient(name) for i = #LOG.client, 1, -1 do if LOG.client[i].name == name then return LOG.client[i] end end end
    """
    
    def server():
        lua = LuaRuntime()
        lua.execute(FAKE_SERVER)
        lua.execute(SERVER)
        return lua, lua.globals()
    
    print("\n--- the player, read fresh ---")
    lua, g = server()
    p = lua.eval("WCore.Functions.GetPlayer(1)")
    check("a doctor's job is a table with the name", p.PlayerData.job.name == "doctor", str(p.PlayerData.job.name))
    check("with the grade level", p.PlayerData.job.grade.level == 3)
    check("off duty to start with", p.PlayerData.job.onduty is False)
    check("the citizenid is VORP's charIdentifier", p.PlayerData.citizenid == "101", str(p.PlayerData.citizenid))
    check("a player with no character is nil", lua.eval("WCore.Functions.GetPlayer(9)") is None)
    check("a VORP character logged out dead starts dead", lua.eval("WCore.Functions.GetPlayer(2).PlayerData.metadata.isdead") is True)
    lua.execute("CHARS[1].job = 'police'")
    check("a job change is seen at once (nothing cached)", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.name") == "police")
    lua.execute("CHARS[1].job = 'doctor'")
    
    ids = lua.eval("WCore.Functions.GetPlayers()")
    check("GetPlayers is an array of server ids with a character", list(ids.values()) == [1, 2], str(list(ids.values())))
    wp = lua.eval("WCore.Functions.GetWPlayers()")
    check("GetWPlayers is keyed by server id", sorted(wp.keys()) == [1, 2], str(list(wp.keys())))
    
    print("\n--- the duty ---")
    lua.execute("fire('WCore:ToggleDuty', 1)")
    check("a doctor goes on duty", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.onduty") is True)
    check("his client is told", lua.eval("lastClient('WCore:Client:SetDuty').args[1]") is True)
    check("and notified", lua.eval("NOTICES[#NOTICES][2]") == "info.on_duty")
    check("every doctor gate now sees him", any(v.PlayerData.job.onduty for v in lua.eval("WCore.Functions.GetWPlayers()").values()))
    lua.execute("fire('WCore:ToggleDuty', 1)")
    check("and off again", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.onduty") is False)
    lua.execute("fire('WCore:ToggleDuty', 2)")
    check("a civilian is never on duty", lua.eval("WCore.Functions.GetPlayer(2).PlayerData.job.onduty") is False)
    # VORP announces a job change BEFORE it stores it: the handler runs with the old job in place
    lua.execute("fire('WCore:ToggleDuty', 1) LOCAL['vorp:playerJobChange'](1, 'police', 'doctor') CHARS[1].job = 'police' flush()")
    check("a job change ends the duty", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.onduty") is False)
    check("and the client gets OnJobUpdate with the NEW job", lua.eval("lastClient('WCore:Client:OnJobUpdate').args[1].name") == "police",
          str(lua.eval("lastClient('WCore:Client:OnJobUpdate') and lastClient('WCore:Client:OnJobUpdate').args[1].name")))
    lua.execute("CHARS[1].job = 'doctor' fire('WCore:ToggleDuty', 1) LOCAL['vorp:playerJobChange'](1, 'doctor', 'doctor') flush()")
    check("picking the same job again (/jobs) keeps the duty", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.onduty") is True)
    lua.execute("LOCAL['vorp:playerJobGradeChange'](1, 5, 3) CHARS[1].jobGrade = 5 flush()")
    check("a promotion reaches the client with the new grade", lua.eval("lastClient('WCore:Client:OnJobUpdate').args[1].grade.level") == 5)
    lua.execute("CHARS[1].jobGrade = 3 fire('WCore:ToggleDuty', 1)")
    lua.execute("fire('WCore:ToggleDuty', 1) source = 1 LOCAL['playerDropped']()")
    check("a drop ends the duty (the next player with this id starts clean)", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.job.onduty") is False)
    
    print("\n--- callbacks: a net event, answered with every value ---")
    lua, g = server()
    lua.execute("WCore.Functions.CreateCallback('hospital:GetPlayerStatus', function(src, cb, target) cb({ BLEED = target }, 'two') end)")
    check("registered as a NET event (a client can reach it)", lua.eval("NET['w_medic:server:cb:hospital:GetPlayerStatus'] ~= nil") is True)
    lua.execute("fire('w_medic:server:cb:hospital:GetPlayerStatus', 1, 7, 42)")
    r = lua.eval("lastClient('w_medic:client:cb')")
    check("the answer goes to the asker, not to the patient", r.src == 1, str(r.src))
    check("with the request id", r.args[2] == 7)
    check("and every value, packed", r.args[3].n == 2 and r.args[3][1].BLEED == 42 and r.args[3][2] == "two")
    lua.execute("WCore.Functions.CreateCallback('boom', function() error('x') end) fire('w_medic:server:cb:boom', 1, 8)")
    check("a handler that throws still answers (no 10 s wait)", lua.eval("lastClient('w_medic:client:cb').args[2]") == 8)
    
    print("\n--- commands ---")
    lua, g = server()
    lua.execute("RAN = {} WCore.Commands.Add('kill', 'h', {}, false, function(src, args) RAN[#RAN+1] = { src, args[1] } end, 'admin')")
    lua.execute("LOG.commands.kill(1, { '5' })")
    check("an admin command refuses a player", lua.eval("#RAN") == 0)
    lua.execute("LOG.commands.kill(3, { '5' })")
    check("and runs for an admin", lua.eval("#RAN") == 1 and lua.eval("RAN[1][2]") == "5")
    lua.execute("LOG.commands.kill(0, {})")
    check("and for the console", lua.eval("#RAN") == 2)
    lua.execute("WCore.Commands.Add('status', 'h', {}, false, function(src) RAN[#RAN+1] = src end)")
    lua.execute("LOG.commands.status(1, {})")
    check("a command with no permission is open (the job check is the handler's)", lua.eval("RAN[#RAN]") == 1)
    
    print("\n--- items ---")
    lua, g = server()
    lua.execute("GOT = nil WCore.Functions.CreateUseableItem('bandage', function(src, item) GOT = { src, item.name, item.slot } end)")
    lua.execute("USABLE.bandage(1, { metadata = {}, slot = 55, item = { id = 55 } })")
    check("the handler gets (source, item) from the bridge", lua.eval("GOT[1]") == 1 and lua.eval("GOT[2]") == "bandage" and lua.eval("GOT[3]") == 55)
    check("RemoveItem is true when the bag removed it", lua.eval("WCore.Functions.GetPlayer(1).Functions.RemoveItem('bandage', 1)") is True)
    check("and FALSE when it did not (a revive is never free)", lua.eval("WCore.Functions.GetPlayer(1).Functions.RemoveItem('syringe', 1)") is False)
    check("the client's HasItem: yes", lua.eval("CALLBACKS['w_medic:hasItem'](1, 'bandage', 1)") is True)
    check("the client's HasItem: no", lua.eval("CALLBACKS['w_medic:hasItem'](1, 'syringe', 1)") is False)
    
    print("\n--- the downed state reaches VORP ---")
    lua.execute("WCore.Functions.GetPlayer(1).Functions.SetMetaData('isdead', true)")
    m = lua.eval("lastClient('w_medic:client:meta')")
    check("the client is told the key", m.args[1] == "isdead" and m.args[2] is True)
    check("with down = true (his client sends vorp:ImDead)", m.args[3] is True)
    check("and the server keeps it", lua.eval("WCore.Functions.GetPlayer(1).PlayerData.metadata.isdead") is True)
    lua.execute("WCore.Functions.GetPlayer(1).Functions.SetMetaData('isdead', false)")
    check("up again: down = false", lua.eval("lastClient('w_medic:client:meta').args[3]") is False)
    
    print("\n--- the offline revive ---")
    lua.execute("local o = WCore.Functions.GetOfflinePlayerByCitizenId('102') o.Functions.SetMetaData('isdead', false) o.Functions.SetMetaData('inlaststand', false) o.Functions.Save()")
    check("a character not in the game is revived on his file", lua.eval("SQL[1] and SQL[1][2][1]") == 0, str(lua.eval("SQL[1] and SQL[1][2][1]")))
    check("an unknown citizen id is nil", lua.eval("WCore.Functions.GetOfflinePlayerByCitizenId('999')") is None)
    
    # ── the client side ────────────────────────────────────────────────────────
    FAKE_CLIENT = r"""
    EV, NET, SENT, FIRED, THREADS = {}, {}, {}, {}, {}
    function GetResourceState(n) return n == 'vorp_core' and 'started' or 'missing' end
    function GetPlayerServerId() return 1 end
    function PlayerId() return 0 end
    function RegisterNetEvent(name, fn) if fn then NET[name] = fn end end
    function AddEventHandler(name, fn) EV[name] = fn end
    function TriggerServerEvent(name, ...) SENT[#SENT + 1] = { name = name, args = table.pack(...) } end
    function TriggerEvent(name, ...) FIRED[#FIRED + 1] = name end
    function CreateThread(fn) THREADS[#THREADS + 1] = fn end
    function SetTimeout(ms, fn) THREADS[#THREADS + 1] = fn end
    function NetworkIsSessionStarted() return true end
    function Wait() end
    function joaat(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
    function runThreads() local t = THREADS THREADS = {} for _, f in ipairs(t) do f() end end
    NOTES = {}
    BAR = true
    w = { notify = function(d) NOTES[#NOTES + 1] = d end,
          progressBar = function(d) LAST_BAR = d return BAR end,
          callback = { await = function(name, delay, item, n) AWAITED = { name, delay, item, n } return item == 'bandage' end } }
    exports = { w_lib = { InvItemLabel = function(_, n) return 'L:' .. n end } }
    function lastSent(name) for i = #SENT, 1, -1 do if SENT[i].name == name then return SENT[i] end end end
    """
    
    def client():
        lua = LuaRuntime()
        lua.execute(FAKE_CLIENT)
        lua.execute(CLIENT)
        return lua, lua.globals()
    
    print("\n--- the client: the player is loaded ---")
    lua, g = client()
    lua.execute("runThreads()")
    check("on start it asks the server for the player", lua.eval("lastSent('w_medic:server:requestPlayerSync') ~= nil") is True)
    lua.execute("NET['w_medic:client:playerSync']({ citizenid = '101', job = { name = 'doctor', grade = { level = 3 }, onduty = false }, metadata = { isdead = true } })")
    check("the first answer fires WCore:Client:OnPlayerLoaded", "WCore:Client:OnPlayerLoaded" in lua.eval("FIRED").values())
    lua.execute("NET['w_medic:client:playerSync']({ citizenid = '101', job = { name = 'doctor', grade = { level = 3 } } })")
    check("only once per character", list(lua.eval("FIRED").values()).count("WCore:Client:OnPlayerLoaded") == 1)
    lua.execute("GOT = nil WCore.Functions.GetPlayerData(function(pd) GOT = pd end)")
    check("GetPlayerData(cb) calls back (the login state is read)", lua.eval("GOT and GOT.job.name") == "doctor")
    check("GetPlayerData() returns it too", lua.eval("WCore.Functions.GetPlayerData().job.grade.level") == 3)
    lua.execute("NET['vorp:SelectedCharacter']() runThreads() NET['w_medic:client:playerSync']({ citizenid = '202', job = 'unemployed' })")
    check("a character switch loads the new one", list(lua.eval("FIRED").values()).count("WCore:Client:OnPlayerLoaded") == 2)
    check("a bare job string is made a table", lua.eval("WCore.Functions.GetPlayerData().job.name") == "unemployed"
          and lua.eval("WCore.Functions.GetPlayerData().job.grade.level") == 0)
    
    print("\n--- the client: VORP's dead flag ---")
    lua.execute("NET['w_medic:client:meta']('isdead', true, true)")
    s = lua.eval("lastSent('vorp:ImDead')")
    check("a downed state sends vorp:ImDead(true)", s is not None and s.args[1] is True)
    check("and the copy is kept", lua.eval("WCore.Functions.GetPlayerData().metadata.isdead") is True)
    lua.execute("NET['w_medic:client:meta']('inlaststand', false, false)")
    check("up again sends vorp:ImDead(false)", lua.eval("lastSent('vorp:ImDead').args[1]") is False)
    
    print("\n--- the client: callbacks, notices, bar, bag ---")
    lua.execute("ANS = nil WCore.Functions.TriggerCallback('hospital:GetPlayerStatus', function(a, b) ANS = { a, b } end, 42)")
    req = lua.eval("lastSent('w_medic:server:cb:hospital:GetPlayerStatus')")
    check("the callback is a server event with the id and the args", req.args[2] == 42)
    lua.execute("NET['w_medic:client:cb']('hospital:GetPlayerStatus', %d, { n = 2, { BLEED = 1 }, 'x' })" % req.args[1])
    check("the answer is unpacked to the caller", lua.eval("ANS[1].BLEED") == 1 and lua.eval("ANS[2]") == "x")
    lua.execute("WCore.Functions.Notify({ text = 'T', caption = 'C' }, 'error') WCore.Functions.Notify('plain', 'primary')")
    check("a notice keeps its text", lua.eval("NOTES[1].title") == "T" and lua.eval("NOTES[1].description") == "C")
    check("and its type", lua.eval("NOTES[1].type") == "error" and lua.eval("NOTES[2].type") == "inform")
    lua.execute("DONE, CANC = 0, 0 WCore.Functions.Progressbar('x', 'L', 3000, false, true, { disableMovement = true }, { animDict = 'd', anim = 'a', flags = 1 }, {}, {}, function() DONE = DONE + 1 end, function() CANC = CANC + 1 end) runThreads()")
    check("a finished bar runs onFinish (the doctor is let go)", lua.eval("DONE") == 1 and lua.eval("CANC") == 0)
    check("with the animation and the controls", lua.eval("LAST_BAR.anim.dict") == "d" and lua.eval("LAST_BAR.disable.move") is True)
    lua.execute("BAR = false WCore.Functions.Progressbar('x', 'L', 3000, false, true, {}, {}, {}, {}, function() DONE = DONE + 1 end, function() CANC = CANC + 1 end) runThreads()")
    check("a cancelled bar runs onCancel", lua.eval("CANC") == 1 and lua.eval("DONE") == 1)
    check("HasItem asks the server: yes", lua.eval("WCore.Functions.HasItem('bandage', 1)") is True)
    check("HasItem: no", lua.eval("WCore.Functions.HasItem('syringe', 1)") is False)
    check("the item goes after the delay argument", lua.eval("AWAITED[2]") is False and lua.eval("AWAITED[3]") == "syringe")
    check("the killer's weapon is found by hash", lua.eval("WCore.Shared.GetWeapon(joaat('weapon_bow')).name") == "weapon_bow")
    
    print("\n%d check(s) failed" % len(fails))
    for f in fails: print("  ! " + f)
    if fails: raise AssertionError('Failed checks: ' + ', '.join(fails))

class LegacyChecks(unittest.TestCase):
    def test_current_resource(self): run_checks()

if __name__ == '__main__': unittest.main()
