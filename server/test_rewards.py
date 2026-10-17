#!/usr/bin/env python3
"""Real native coupon integration. Writes only fresh dev fixtures; never operator accounts."""
import argparse, json, os, pathlib, sqlite3, time
from eo_session import Session, EOError, Reader
from live_session import LiveSession
from test_online import provision, dev_name
from run import state_path

def quantities(session):
    return {i: session.item_amount(i) for i in (375, 1, 421)}

def rejection(session, code, text):
    time.sleep(1.05)
    try:session.redeem_code(code)
    except EOError as exc:assert text in str(exc), str(exc)
    else:raise AssertionError('Coupon unexpectedly accepted')

def login(fixture):
    s=LiveSession();data=s.login(fixture['username'], fixture['password']);character=next(c for c in data['characters'] if c['name']==fixture['character_name']);s.enter(character['id']);return s

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir');parser.add_argument('--report',type=pathlib.Path)
    parser.add_argument('--fault-tests',action='store_true',help='Dev-only SQLite fixtures/trigger for rollback and capacity tests')
    a=parser.parse_args();dbpath=state_path(a.state_dir)/'runtime/database.sdb'
    raw,fixture=provision();raw.close();time.sleep(.7)
    s=login(fixture);before=quantities(s);report={}
    try:
        rejection(s,'BOGUS123','not valid');assert quantities(s)==before
        report['invalid_code_no_grant']=True
        # Native reply must persist rewards before the connection can be lost.
        time.sleep(1.05);s.redeem_code(' kcpd108 ')
        after={375:before[375]+1000,1:before[1]+50000,421:before[421]+1}
        assert quantities(s)==after
        report['exact_native_rewards']={'big_health_potions':1000,'gold':50000,'lens_of_truth':1}
        with sqlite3.connect(dbpath) as db:
            row=db.execute('SELECT inventory FROM characters WHERE name=?',(fixture['character_name'],)).fetchone()
            saved={int(p.split(',')[0]):int(p.split(',')[1]) for p in row[0].split(';') if p}
            assert all(saved.get(i,0)==n for i,n in after.items())
            assert db.execute('SELECT COUNT(*) FROM aster_coupon_redemptions WHERE account=?',(fixture['username'],)).fetchone()[0]==1
        report['persisted_before_logout']=True
        rejection(s,'KCPD108','already redeemed');assert quantities(s)==after
        report['duplicate_no_grant']=True
    finally:s.close()
    time.sleep(.8);s=login(fixture)
    try:
        assert quantities(s)==after
        rejection(s,'KCPD108','already redeemed');assert quantities(s)==after
    finally:s.close()
    report['reconnect_does_not_reset_coupon']=True
    time.sleep(.8);raw=Session();raw.login(fixture['username'],fixture['password']);data=raw.create_character(dev_name());raw.close()
    other=next(c for c in data['characters'] if c['name']!=fixture['character_name'])
    time.sleep(.8);second=dict(fixture,character_id=other['id'],character_name=other['name']);s=login(second)
    try:
        before_second=quantities(s);rejection(s,'KCPD108','already redeemed');assert quantities(s)==before_second
    finally:s.close()
    report['second_character_same_account_cannot_redeem']=True
    if a.fault_tests:
        raw,fault=provision();raw.close();time.sleep(.8)
        assert fault['username'].startswith('dev') and fault['character_name'].startswith('dev')
        # Fail ledger insertion after Character::Save to exercise both rollback paths.
        with sqlite3.connect(dbpath) as db:
            db.execute("CREATE TRIGGER test_reward_abort BEFORE INSERT ON aster_coupon_redemptions WHEN NEW.account='%s' BEGIN SELECT RAISE(ABORT,'dev rollback test'); END" % fault['username'])
        s=login(fault);old=quantities(s)
        try:
            rejection(s,'KCPD108','unavailable');assert quantities(s)==old
            with sqlite3.connect(dbpath) as db:
                saved=db.execute('SELECT inventory FROM characters WHERE name=?',(fault['character_name'],)).fetchone()[0]
                assert '375,1000;' not in saved and '421,1;' not in saved
                assert db.execute('SELECT COUNT(*) FROM aster_coupon_redemptions WHERE account=?',(fault['username'],)).fetchone()[0]==0
            report['database_failure_rolls_back_inventory_and_ledger']=True
        finally:
            s.close();time.sleep(1)
            with sqlite3.connect(dbpath) as db:db.execute('DROP TRIGGER IF EXISTS test_reward_abort')
        time.sleep(.8);s=login(fault)
        try:s.redeem_code('KCPD108');assert quantities(s)=={375:old[375]+1000,1:old[1]+50000,421:old[421]+1}
        finally:s.close()
        report['failed_redemption_can_retry']=True
        raw,capacity=provision();raw.close();time.sleep(.8)
        assert capacity['character_name'].startswith('dev')
        with sqlite3.connect(dbpath) as db:
            db.execute("UPDATE characters SET inventory='375,2000000000;' WHERE name=?",(capacity['character_name'],))
        s=login(capacity)
        try:
            old=quantities(s);rejection(s,'KCPD108','item limit');assert quantities(s)==old
            with sqlite3.connect(dbpath) as db:assert db.execute('SELECT COUNT(*) FROM aster_coupon_redemptions WHERE account=?',(capacity['username'],)).fetchone()[0]==0
        finally:s.close()
        report['capacity_failure_no_partial_reward_or_consumed_code']=True
    report.update(result='passed',native_protocol='Redeem 230/1 -> 230/3',operator_accounts_touched=False)
    if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
