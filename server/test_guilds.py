"""Native guild lifecycles, rejection, async ordering and authoritative receipts."""
import unittest
from unittest.mock import patch
from eo_session import EOError, number, string
from test_live_state import fixture

class Socket:
    def settimeout(self,seconds):pass

class GuildTests(unittest.TestCase):
    def opened(self):
        s=fixture();s.sock=Socket();s.state['self']['name']='devfounder'
        s.state['npcs']=[dict(id=60,index=7,x=40,y=39)]
        s.snapshot=lambda:dict(guild=s.guild,creation=s.guild_creation)
        s._guild_sync=lambda:None
        s.packets=[(39,13,number(123,3))]
        s.receive=lambda:s.packets.pop(0)
        with patch('guilds.npc_types',return_value={60:11}):s.guild_open(7)
        return s

    def test_open_requires_native_ack_and_correct_npc_type(self):
        s=self.opened();self.assertEqual(s.sent,[(39,13,number(7,2))]);self.assertEqual(s.guild['token'],123)
        with patch('guilds.npc_types',return_value={60:9}):
            with self.assertRaises(EOError):s.guild_open(7)
        with patch('guilds.npc_types',return_value={60:11}):
            s._guild_wait=lambda *args:(_ for _ in ()).throw(EOError('Rejected'))
            with self.assertRaises(EOError):s.guild_open(7)
        self.assertIsNone(s.guild)

    def test_information_members_and_not_found_match_native_builders(self):
        s=self.opened();payload=b''.join(string(v) for v in ('Test Guild','TST','2026-10-23','Description','50000'))
        payload+=b''.join(string('Rank '+str(i)) for i in range(9))+number(1,2)+b'\xff'+number(1,1)+b'\xff'+string('devleader (founder)')
        s.packets=[(39,21,payload)]
        result=s.guild_lookup('tst')['guild']['result'];self.assertEqual(result['leaders'],[dict(role=1,name='devleader (founder)')])
        self.assertEqual(s.sent[-1],(39,21,number(123,4)+b'TST'))
        payload=number(1,2)+b'\xff'+number(9,1)+b'\xff'+string('devmember')+string('Member')
        s.packets=[(39,20,payload)];self.assertEqual(s.guild_lookup('Test Guild',True)['guild']['result']['members'][0]['name'],'devmember')
        for width in (1,2):
            s.packets=[(39,3,number(17,width))]
            with self.assertRaisesRegex(EOError,'Guild not found'):s.guild_lookup('TST')

    def test_bad_payload_never_publishes_partial_members(self):
        s=self.opened();s.packets=[(39,20,number(1,2)+b'\xff'+number(0,1)+b'\xff'+string('truncated'))]
        with self.assertRaises((RuntimeError,ValueError)):s.guild_lookup('TST',True)
        self.assertNotIn('result',s.guild)

    def test_invalid_queries_and_stale_context_never_send_packets(self):
        s=self.opened();s.sent.clear()
        for query in ('','X','X'*25,'TST\xff','TST\0','!!!'):
            with self.assertRaises(EOError):s.guild_lookup(query)
        s.state['self']['x']=100
        with self.assertRaises(EOError):s.guild_lookup('TST')
        s.state['self']['x']=40;s.state['map_id']=6
        with self.assertRaises(EOError):s.guild_lookup('TST')
        s.guild_close()
        with self.assertRaises(EOError):s.guild_lookup('TST')
        self.assertEqual(s.sent,[])

    def test_founder_approval_is_server_driven_and_gold_waits_for_create(self):
        s=self.opened();s.inventory=[dict(id=1,amount=60000)]
        s.packets=[(39,3,number(6,1))];s.guild_begin('tst','Test Guild')
        self.assertFalse(s.guild_creation['ready']);self.assertEqual(s.item_amount(1),60000)
        with self.assertRaises(EOError):s.guild_found('Welcome')
        s.apply_event(39,3,number(8,2)+b'devsupport');self.assertFalse(s.guild_creation['ready'])
        s.apply_event(39,3,number(7,2)+b'devsupport');self.assertTrue(s.guild_creation['ready']);self.assertEqual(len(s.guild_creation['members']),2)
        s.packets=[(39,6,number(100,2)+b'\xff'+string('TST')+string('test guild')+string('Leader')+number(10000,4))]
        s.guild_found('Welcome');self.assertIsNone(s.guild_creation);self.assertEqual(s.item_amount(1),10000);self.assertEqual(s.stats['guild_tag'],'TST')
        self.assertEqual(s.sent[-1],(39,6,number(123,4)+b'\xff'+string('TST')+string('test guild')+string('Welcome')))

    def test_support_and_join_do_not_grant_optimistic_membership(self):
        s=self.opened();s.apply_event(39,1,number(200,2)+b'Test guild (TST)');s.guild_support(True)
        self.assertEqual(s.sent[-1],(39,2,b''));self.assertNotIn('guild',s.stats)
        s.guild_join('tst','DevRecruiter');self.assertNotIn('guild',s.stats)
        self.assertEqual(s.sent[-1],(39,8,number(123,4)+b'\xff'+string('TST')+string('devrecruiter')))
        s.apply_event(39,5,number(200,2)+b'\xff'+string('TST')+string('test guild')+string('New Member')+b'\xff')
        self.assertEqual(s.stats['guild'],'test guild')

    def test_async_application_cannot_satisfy_a_deposit_ack(self):
        s=self.opened();s.inventory=[dict(id=1,amount=5000)]
        s._guild_member=lambda *args:dict(bank=0,rank=0)
        s.packets=[(39,3,number(13,2)+number(201,2)+b'DevJoiner'),(39,11,number(4000,4))]
        s.guild_deposit(1000)
        self.assertEqual(s.item_amount(1),4000);self.assertEqual(s.guild_requests[0]['player_id'],201)
        self.assertEqual(s.sent[-1],(39,11,number(123,4)+number(1000,4)))

    def test_insufficient_bank_keeps_application_for_retry(self):
        s=self.opened();s.apply_event(39,3,number(13,2)+number(201,2)+b'DevJoiner');s.packets=[(39,3,number(15,2))]
        with self.assertRaisesRegex(EOError,'bank'):s.guild_recruit(201,True)
        self.assertEqual(len(s.guild_requests),1)
        s.packets=[(39,3,number(16,2))];s.guild_recruit(201,True);self.assertEqual(s.guild_requests,[])

    def test_rank_admin_validations_and_native_acks(self):
        s=self.opened();s._guild_member=lambda *args:dict(rank=1,tag='TST');s._guild_read=lambda *args:dict(members=[dict(name='devmember',rank=9)])
        s.packets=[(39,3,number(18,2))];s.guild_rank('devmember',2)
        self.assertEqual(s.sent[-1],(39,29,number(123,4)+number(2,1)+b'devmember'))
        count=len(s.sent)
        with self.assertRaises(EOError):s.guild_rank('devmember',0)
        with self.assertRaises(EOError):s.guild_rank('devmember',10)
        self.assertEqual(len(s.sent),count)
        s.packets=[(39,3,number(22,2))];s.guild_kick('devmember')
        self.assertEqual(s.sent[-1],(39,28,number(123,4)+b'devmember'))

    def test_native_text_constraints_and_all_nine_ranks(self):
        s=self.opened();s._guild_member=lambda *args:dict(rank=0)
        for value,kind in [('a1','tag'),('bad name!','name'),('A'*17,'rank'),('Line\nbreak','description'),('bad name','character')]:
            with self.assertRaises(EOError):s._guild_text(value,kind)
        with self.assertRaises(EOError):s.guild_ranks('Only,Two')
        s.packets=[(39,3,number(19,2))];s.guild_ranks('Leader,Recruiter,,,,,,,Member')
        self.assertEqual(s.sent[-1],(39,5,number(123,4)+number(2,2)+b''.join(string(v) for v in ['Leader','Recruiter','','','','','','','Member'])))

    def test_decline_never_sends_accept_or_changes_membership(self):
        s=self.opened();s.apply_event(39,1,number(200,2)+b'Test guild (TST)');count=len(s.sent);s.guild_support(False)
        self.assertEqual(len(s.sent),count);self.assertIsNone(s.guild_invitation)
        s.apply_event(39,3,number(13,2)+number(201,2)+b'DevJoiner');s.guild_recruit(201,False)
        self.assertEqual(len(s.sent),count);self.assertEqual(s.guild_requests,[])

    def test_movement_clears_service_context(self):
        s=self.opened();s.move(3,1,5,41,40);self.assertIsNone(s.guild)

if __name__=='__main__':unittest.main()
