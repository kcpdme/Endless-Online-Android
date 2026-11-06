import hashlib,json,tempfile,unittest,os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from combat_progression import BOWS,equipped_combat,CLIENT_ATTACK_SECONDS
from configure_attack_cadence import configure

class AttackCadenceTests(unittest.TestCase):
    def test_all_classes_ignore_stale_fast_bow_and_close_bonuses(self):
        items={'457':dict(type=10,subtype=1,range_tiles=7,attack_speed=1.5,close_attack_speed=2,close_range=2,shot_power=.7),'424':dict(subtype=2,range_bonus=2)}
        with patch('balance_rules.profile',return_value=dict(items=items)):
            for clas in range(9):
                s=SimpleNamespace(stats=dict(class_id=clas,level=50),equipment=dict(weapon=457,offhand=424))
                combat=equipped_combat(s)
                self.assertEqual(combat['attack_seconds'],CLIENT_ATTACK_SECONDS)
                self.assertEqual(combat['close_attack_seconds'],CLIENT_ATTACK_SECONDS)
                self.assertEqual(combat['close_range'],0)
                self.assertEqual(combat['range_tiles'],9 if clas==5 else 1)
                self.assertEqual(combat['shot_power'],.7 if clas==5 else 1)
                self.assertEqual(combat['adjacent_npc_damage_multiplier'],1.2 if clas==5 else 1)
    def test_targeted_migration_preserves_stats_rewards_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            r=Path(tmp);(r/'data').mkdir()
            items={str(i):dict(type=10,subtype=1,attack_speed=2,close_attack_speed=2,close_range=2,min_damage=i,range_tiles=v['range_tiles'],shot_power=.7) for i,v in BOWS.items()}
            profile=dict(version=15,items=items,classes={'5':{'signature':{'description':'Old x2 bow speed'}},'6':{'signature':{'name':'Might'}}},spells={'1':{'tp':7}},npcs={'1':{'exp':5}},companions={'61':{'power':1.5}})
            (r/'data/balance-profile.json').write_text(json.dumps(profile))
            (r/'config.local.ini').write_text('PrivateSetting = preserved\nBalanceItem.457.attack_speed = 2\nBalanceItem.457.close_attack_speed = 2\nBalanceItem.457.shot_power = .7\nBalanceItem.457.range_tiles = 7\nExpRate = 200%\n')
            (r/'data/balance-v1-manifest.json').write_text(json.dumps(dict(installed={'config.local.ini':'before','data/balance-profile.json':'before'})))
            (r/'config.local.ini').chmod(0o600)
            original_stat=Path.stat
            owner=original_stat(r/'config.local.ini')
            def root_created_pending(path,*args,**kwargs):
                stat=original_stat(path,*args,**kwargs)
                if path.name.endswith('.cadence-pending'):
                    values=list(stat);values[4]=stat.st_uid+1;values[5]=stat.st_gid+1
                    return os.stat_result(values)
                return stat
            with patch.object(Path,'stat',root_created_pending),patch('configure_attack_cadence.os.chown') as chown:
                configure(r)
                self.assertTrue(any(call.args==(r/'config.local.ini.cadence-pending',owner.st_uid,owner.st_gid) for call in chown.call_args_list))
            self.assertEqual((r/'config.local.ini').stat().st_mode&0o777,0o600)
            after=json.loads((r/'data/balance-profile.json').read_text())
            for key in ('spells','npcs','companions'):self.assertEqual(after[key],profile[key])
            self.assertIn('classic',after['classes']['5']['signature']['description'])
            self.assertEqual(after['classes']['6'],profile['classes']['6'])
            self.assertEqual(after['attack_timing']['archer_adjacent_npc_damage_multiplier'],1.2)
            for ident,item in after['items'].items():
                self.assertEqual(item['attack_speed'],1);self.assertNotIn('close_attack_speed',item);self.assertNotIn('close_range',item)
                self.assertEqual(item['shot_power'],1)
                for key in ('range_tiles','min_damage'):self.assertEqual(item[key],items[ident][key])
            config=(r/'config.local.ini').read_text()
            self.assertIn('PrivateSetting = preserved\n',config);self.assertIn('ExpRate = 200%\n',config);self.assertIn('BalanceItem.457.range_tiles = 7\n',config)
            self.assertIn('BalanceItem.457.shot_power = 1.0\n',config)
            self.assertNotIn('shot_power = .7',config)
            manifest=json.loads((r/'data/balance-v1-manifest.json').read_text())
            for rel,h in manifest['installed'].items():self.assertEqual(hashlib.sha256((r/rel).read_bytes()).hexdigest(),h)
            self.assertEqual(configure(r)['files_changed'],[])
            self.assertEqual({p.name for p in r.iterdir()},{'data','config.local.ini'})

if __name__=='__main__':unittest.main()
