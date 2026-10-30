'''Current handout fallback: server job, duty, proximity, capacity and finite stock.'''
from pathlib import Path
import unittest
from lupa import lua54
SOURCE = (Path(__file__).resolve().parents[1] / 'server/main.lua').read_text(encoding='utf-8-sig')
HANDOUT = SOURCE[SOURCE.index('local function activeBag()'):SOURCE.index('--- The armory prompt. Which shelf it opens')]
class PharmacyTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua54.LuaRuntime()
        self.lua.execute('''
GIVEN=0;NOW=0;DUTY=true;JOB='doctor';FAR=false;CARRY=true;ADDED=true
local mt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},getmetatable(a)) end,__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}
function vector3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
Config={Pharmacy={enabled=true,useStore=false,stock={bandage=3},windowMinutes=60,maxPerWindow=2,maxPerVisit=1,perVisit={bandage=1}},Locations={armory={{coords=vector3(0,0,0)}}}}
WCore={Functions={GetPlayer=function() return {PlayerData={job={name=JOB,onduty=DUTY}}} end}}
function GetResourceState() return 'started' end
function GetGameTimer() return NOW end
function GetPlayerPed(src) return src end
function GetEntityCoords() return vector3(FAR and 100 or 0,0,0) end
function TriggerClientEvent() end
exports={w_lib={InvName=function() return 'vorp_inventory' end,InvCanCarry=function() return CARRY end,
InvAddItem=function(_,src,item,n) if ADDED then GIVEN=GIVEN+n end return ADDED end}}
''')
        self.lua.execute(HANDOUT + '\nTEST_SETUP=setupPharmacy;TEST_TAKE=takeSupplies;TEST_SETUP()')
    def test_only_duty_doctor_near_cabinet(self):
        self.lua.execute("JOB='citizen';assert(not TEST_TAKE(1));JOB='doctor';DUTY=false;assert(not TEST_TAKE(1));DUTY=true;FAR=true;assert(not TEST_TAKE(1));assert(GIVEN==0)")
    def test_capacity_and_failed_add_preserve_stock(self):
        self.lua.execute("CARRY=false;assert(not TEST_TAKE(1));CARRY=true;ADDED=false;assert(not TEST_TAKE(1));ADDED=true;assert(TEST_TAKE(1) and GIVEN==1)")
    def test_per_player_window_is_enforced(self):
        self.lua.execute("assert(TEST_TAKE(1));assert(TEST_TAKE(1));assert(not TEST_TAKE(1));assert(GIVEN==2);NOW=3600001;assert(TEST_TAKE(1));assert(GIVEN==3)")
    def test_shared_stock_cannot_be_duplicated_across_players(self):
        self.lua.execute("assert(TEST_TAKE(1));assert(TEST_TAKE(2));assert(TEST_TAKE(3));assert(not TEST_TAKE(4));assert(GIVEN==3)")
if __name__ == '__main__': unittest.main()
