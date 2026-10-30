"""Actual server/client handlers in isolated Lua; no money, database, game or network."""
from pathlib import Path
import unittest
from lupa import lua54

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'server/main.lua').read_text(encoding='utf-8-sig')

class PatientAndHiring(unittest.TestCase):
    def injuries(self):
        lua=lua54.LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''H={}; C={}; source=1; NOW=1000; PlayerInjuries={}; PlayerWeaponWounds={}
function GetGameTimer() return NOW end
function RegisterNetEvent(k,fn) H[k]=fn end
function AddEventHandler() end
WCore={Functions={GetPlayer=function(id)return{PlayerData={source=id}}end,CreateCallback=function(k,fn)C[k]=fn end}}
''')
        a=SOURCE.index('-- The client reports its own injuries')
        b=SOURCE.index("RegisterNetEvent('hospital:server:RestoreWeaponDamage'",a)
        lua.execute(SOURCE[a:b])
        a=SOURCE.index("WCore.Functions.CreateCallback('hospital:GetPlayerStatus'")
        b=SOURCE.index("WCore.Functions.CreateCallback('hospital:GetPlayerBleeding'",a)
        lua.execute(SOURCE[a:b])
        return lua

    def test_normal_injuries_and_server_owned_labels(self):
        lua=self.injuries()
        lua.execute("H['hospital:server:SyncInjuries']({isBleeding=2,limbs={HEAD={isDamaged=true,severity=2,label='forged'}}}); C['hospital:GetPlayerStatus'](2,function(v)R=v end,1)")
        self.assertEqual(lua.globals().R['HEAD']['label'],'body.head')
        self.assertEqual(lua.globals().R['BLEED'],2)

    def test_malformed_reports_do_not_poison_existing_state(self):
        lua=self.injuries()
        lua.execute("H['hospital:server:SyncInjuries']({isBleeding=0,limbs={}}); NOW=2000; for _,v in ipairs({{}, {isBleeding=0,limbs='bad'}, {isBleeding=0,limbs={HEAD={isDamaged=true,severity=0/0}}}, {isBleeding=0,limbs={FAKE={isDamaged=true,severity=1}}}}) do H['hospital:server:SyncInjuries'](v) end; C['hospital:GetPlayerStatus'](2,function(v)R=v end,1)")
        self.assertIsNotNone(lua.globals().R)
        self.assertEqual(len(lua.globals().R['WEAPONWOUNDS']),0)
        lua.execute("H['hospital:server:SetWeaponDamage']('bad'); H['hospital:server:SetWeaponDamage']({{}}); H['hospital:server:SetWeaponDamage']({'WEAPON_REVOLVER_CATTLEMAN'})")
        self.assertEqual(lua.globals().PlayerWeaponWounds[1][1],'WEAPON_REVOLVER_CATTLEMAN')

    def hiring(self):
        lua=lua54.LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''C={}; HIRED=nil; function jobsGate()return{}end; function jobsFail(reason)return{ok=false,error=reason}end
function mayGive(_,grade)return grade==2 end;function rankLabel()return'Doctor'end
function fwc(key,id)if key=='GetJob'then return'citizen'else return'char-'..id end end
function GetPlayerName(id)return'Player '..id end
function setJobOnline(id,job,grade,label)HIRED=id;return true end
w={notify=function()end,callback={register=function(k,fn)C[k]=fn end},citizen={}}
w.citizen.requireOnline=function(input)if input=='777'or input=='#5'then return{source=5,citizenid='777',name='Chosen Citizen'}elseif input=='5'then return{source=2,citizenid='5',name='Different Citizen'}end end
w.citizen.label=function(who)return who.name..' ['..who.citizenid..']'end
''')
        a=SOURCE.index('-- A named citizen preview')
        b=SOURCE.index('--- A doctor (in the game or not)',a)
        lua.execute(SOURCE[a:b])
        return lua

    def test_hiring_uses_named_citizen_and_rechecks_identity(self):
        lua=self.hiring()
        lua.execute("R=C['w_medic:jobs:previewHire'](1,'#5',2)")
        self.assertEqual(lua.globals().R['citizenid'],'777')
        lua.execute("R=C['w_medic:jobs:hire'](1,'5',2,'777')")
        self.assertFalse(lua.globals().R['ok'])
        self.assertIsNone(lua.globals().HIRED)
        lua.execute("R=C['w_medic:jobs:hire'](1,'777',2,'777')")
        self.assertTrue(lua.globals().R['ok'])
        self.assertEqual(lua.globals().HIRED,5)

    def test_old_or_unconfirmed_hire_request_is_refused(self):
        lua=self.hiring()
        lua.execute("R=C['w_medic:jobs:hire'](1,'777',2)")
        self.assertFalse(lua.globals().R['ok'])
        self.assertIsNone(lua.globals().HIRED)

    def test_cancelled_name_confirmation_does_not_send_hire(self):
        lua=lua54.LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''CALLS={};function rankOptions()return{{value='2'}}end;function locale(k,...)return k end;function openCenter()end;function tell()end
w={inputDialog=function()return{'777',2}end,alertDialog=function()return'cancel'end,callback={await=function(name,...)CALLS[#CALLS+1]=name;return{ok=true,citizenid='777',name='Chosen',label='Doctor'}end}}
''')
        source=(ROOT/'client/jobs_center.lua').read_text(encoding='utf-8-sig')
        a=source.index('local function hireDialog(');b=source.index('-- the ranks',a)
        run=lua.execute(source[a:b]+'\nreturn hireDialog')
        run(lua.table_from({'ranks':lua.table()}))
        self.assertEqual(len(lua.globals().CALLS),1)
        self.assertEqual(lua.globals().CALLS[1],'w_medic:jobs:previewHire')

if __name__=='__main__':unittest.main()
