import pathlib
import re
import unittest
from lupa.lua54 import LuaRuntime

RESOURCE = pathlib.Path(__file__).resolve().parents[1]
CHECKS = [('server/main.lua', 'isAdminSrc')]
NODE = 'w_medic.admin'

class SitePermissionGate(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            nodes = {}; admins = {}
            function IsPlayerAceAllowed(src,node) return (nodes[src] or {})[node] == true end
            exports={w_lib={}}
            function exports.w_lib:IsAdmin(src) return admins[src] == true end
            function exports.w_lib:HasPermissionNode(src,node) return src==0 or admins[src]==true or IsPlayerAceAllowed(src,node) end
        """)
        self.gates = []
        for filename, name in CHECKS:
            text = (RESOURCE / filename).read_text(encoding='utf-8-sig')
            start = re.search(r'local function '+re.escape(name)+r'\(', text).start()
            tail = text[start:]; first = tail.splitlines()[0]
            body = first if first.rstrip().endswith(' end') else tail.split('\nend',1)[0]+'\nend'
            self.lua.execute(body+'\n tested='+name)
            self.gates.append(self.lua.globals().tested)

    def grant(self,node): self.lua.globals().nodes[7] = self.lua.table_from({node: True})
    def test_unassigned_player_is_refused(self):
        for gate in self.gates: self.assertFalse(gate(7))
    def test_exact_script_scope_is_allowed(self):
        self.grant(NODE)
        for gate in self.gates: self.assertTrue(gate(7))
    def test_other_script_scope_is_refused(self):
        self.grant('w_unrelated.admin')
        for gate in self.gates: self.assertFalse(gate(7))
    def test_existing_manual_admin_is_preserved(self):
        self.lua.globals().admins[7] = True
        for gate in self.gates: self.assertTrue(gate(7))
    def test_revocation_is_checked_on_next_call(self):
        self.grant(NODE)
        for gate in self.gates: self.assertTrue(gate(7))
        self.lua.globals().nodes[7] = self.lua.table_from({})
        for gate in self.gates: self.assertFalse(gate(7))

if __name__=='__main__': unittest.main()
