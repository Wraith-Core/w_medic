'''Current doctor payment contract: doctor receives the fee, with patient-specific keys.'''
from pathlib import Path
import unittest
from lupa import lua54
SOURCE = (Path(__file__).resolve().parents[1] / 'server/main.lua').read_text(encoding='utf-8-sig')
PAY = SOURCE[SOURCE.index('local function bankUp()'):SOURCE.index('--- The salary of every doctor')]
class PayTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua54.LuaRuntime()
        self.lua.execute('''
T={};NOTES={};NOW=1000;BANK=true
Config={Pay={enabled=true,treat=20,revive=30}}
WCore={Functions={GetPlayer=function(src) if src<10 then return {PlayerData={citizenid='C'..src,source=src}} end end}}
function GetGameTimer() return NOW end
function GetResourceState() return BANK and 'started' or 'missing' end
exports={w_centralbank={IsReady=function() return true end,EnsureAccount=function() return true end,
Transfer=function(_,from,to,amount,key) T[#T+1]={from=from,to=to,amount=amount,key=key};return true end},
w_lib={
EconName=function() return BANK and 'w_centralbank' or 'framework' end,
EconIsReady=function() return BANK end,
EconEnsureAccount=function() return BANK end,
EconTransfer=function(_,from,to,amount,reason,key) if not BANK then return false end T[#T+1]={from=from,to=to,amount=amount,reason=reason,key=key or reason};return true end,
FwAddCurrency=function() return false end}}
w={notify=function(src,data) NOTES[#NOTES+1]={src=src,data=data} end}
''')
        self.lua.execute(PAY + '\nTEST_PAY=payDoctor')
    def test_fee_credits_doctor_not_patient(self):
        self.lua.execute("assert(TEST_PAY(1,2,'treat'));assert(T[1].from=='society:doctor' and T[1].to=='player:C1:bank' and T[1].amount==20 and NOTES[1].src==1)")
    def test_key_separates_doctor_patient_kind_and_time(self):
        self.lua.execute("TEST_PAY(1,2,'treat');TEST_PAY(2,3,'treat');NOW=1001;TEST_PAY(1,2,'revive');assert(#T==3 and T[1].key~=T[2].key and T[1].key~=T[3].key and T[3].amount==30)")
    def test_unknown_patient_disabled_pay_and_failed_fallback(self):
        self.lua.execute("assert(not TEST_PAY(1,99,'treat'));Config.Pay.enabled=false;assert(not TEST_PAY(1,2,'treat'));Config.Pay.enabled=true;BANK=false;assert(not TEST_PAY(1,2,'treat'));assert(#T==0 and #NOTES==0)")
if __name__ == '__main__': unittest.main()
