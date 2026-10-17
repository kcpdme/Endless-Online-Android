"""Reward acknowledgement parsing and trust boundaries (no client-side grants)."""
import unittest
from rewards import RewardsMixin
from eo_session import EOError, number

class FakeRewards(RewardsMixin):
    def __init__(self):
        self.inventory={375:7,1:19,421:0};self.stats={};self.dirty=False;self.sent=[]
    def _standing(self):pass
    def _set_amount(self,item,amount):self.inventory[item]=amount
    def send(self,*args):self.sent.append(args)
    def _wait_service(self,*args,**kwargs):
        self.apply_reward_packet(230,3,self.reply)
        return self.reply
    def snapshot(self):return {'inventory':dict(self.inventory)}

def success():
    return number(0,1)+number(250,1)+number(70,1)+b''.join(number(i,2)+number(a,4) for i,a in ((375,1007),(1,50019),(421,1)))

class RewardStateTests(unittest.TestCase):
    def test_invalid_codes_never_sent(self):
        for code in ('','bad!','A'*33,'é'):
            s=FakeRewards()
            with self.assertRaises(EOError):s.redeem_code(code)
            self.assertEqual(s.sent,[])
    def test_acknowledged_totals_replace_not_add(self):
        s=FakeRewards();s.reply=success()
        result=s.redeem_code(' kcpd108 ')
        self.assertEqual(s.sent,[(230,1,b'KCPD108\xff')])
        self.assertEqual(result['inventory'],{375:1007,1:50019,421:1})
        s.apply_reward_packet(230,3,s.reply)
        self.assertEqual(s.inventory,{375:1007,1:50019,421:1})
    def test_rejection_does_not_change_bag(self):
        for status in (1,2,3,4):
            s=FakeRewards();s.reply=number(status,1)
            with self.assertRaises(EOError):s.redeem_code('KCPD108')
            self.assertEqual(s.inventory,{375:7,1:19,421:0})
    def test_malformed_success_is_atomic(self):
        s=FakeRewards()
        for payload in (success()[:-1],success()+b'?',success()[:3]+number(21,2)+success()[5:]):
            with self.assertRaises(EOError):s.apply_reward_packet(230,3,payload)
            self.assertEqual(s.inventory,{375:7,1:19,421:0})
    def test_retry_rate_limit(self):
        s=FakeRewards();s.reply=success();s.redeem_code('KCPD108')
        with self.assertRaises(EOError):s.redeem_code('KCPD108')
        self.assertEqual(len(s.sent),1)

if __name__=='__main__':unittest.main()
