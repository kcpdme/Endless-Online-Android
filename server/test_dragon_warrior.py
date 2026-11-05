import hashlib, json, os, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
from configure_dragon_warrior import configure
from dragon_warrior import add_recipes


class DragonWarriorTests(unittest.TestCase):
    def fixture(self, root):
        data = root/'data'; data.mkdir()
        (data/'aster-vale-shops.ini').write_text('Version = 1\n253.name = Dragon Warrior\n253.trade = 469,0,250\n253.craft = \n36.craft = 21,258,2,0,0,0,0,0,0\n')
        profile = dict(version=15, items={str(i):dict(name=name,gender=gender,type=12,hp=101,armor=20,crafted=False,acquisition=dict(drop=[225])) for i,name,gender in ((458,'Draco',1),(459,'Dracota',0))}, other=dict(preserved=True))
        (data/'balance-profile.json').write_text(json.dumps(profile,indent=2)+'\n')
        (data/'aster-vale-drops.ini').write_text('225 = 456,1,1,1,458,1,1,1,459,1,1,1\n')
        manifest = dict(version=15, installed={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in data.iterdir()})
        (data/'balance-v1-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        for p in data.iterdir(): p.chmod(0o640)
        return profile

    def test_adds_only_the_two_recipes_and_preserves_classic_trade_and_stats(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); old = self.fixture(root)
            drops = (root/'data/aster-vale-drops.ini').read_bytes()
            owner = (root/'data/aster-vale-shops.ini').stat()
            original_stat = Path.stat
            def foreign_pending(path, *args, **kwargs):
                stat = original_stat(path,*args,**kwargs)
                if path.name.endswith('.dragon-pending'):
                    values = list(stat); values[4] += 1; values[5] += 1
                    return os.stat_result(values)
                return stat
            with patch.object(Path,'stat',foreign_pending), patch('configure_dragon_warrior.os.chown') as chown:
                report = configure(root)
                self.assertEqual(chown.call_count,3)
                self.assertTrue(all(call.args[1:]==(owner.st_uid,owner.st_gid) for call in chown.call_args_list))
            self.assertFalse(report['drops_changed']); self.assertFalse(report['database_opened'])
            text = (root/'data/aster-vale-shops.ini').read_text()
            self.assertIn('253.trade = 469,0,250\n',text)
            self.assertIn('253.craft = 458,469,10,470,10,1,200,0,0,459,469,10,470,10,1,200,0,0\n',text)
            self.assertIn('36.craft = 21,258,2,0,0,0,0,0,0\n',text)
            after = json.loads((root/'data/balance-profile.json').read_text())
            for key,item in after['items'].items():
                self.assertEqual(item['acquisition']['craft'],[253])
                del item['acquisition']['craft']
                self.assertEqual(item,old['items'][key])
            self.assertEqual((root/'data/aster-vale-drops.ini').read_bytes(),drops)
            for p in (root/'data').iterdir(): self.assertEqual(p.stat().st_mode&0o777,0o640)
            manifest = json.loads((root/'data/balance-v1-manifest.json').read_text())
            for rel,expected in manifest['installed'].items(): self.assertEqual(hashlib.sha256((root/rel).read_bytes()).hexdigest(),expected)
            self.assertEqual(configure(root)['files_changed'],[])

    def test_rejects_changed_content_before_any_write(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); self.fixture(root)
            (root/'data/aster-vale-shops.ini').write_text('Version = 1\n253.craft = operator-change\n')
            before = {p:p.read_bytes() for p in (root/'data').iterdir()}
            with self.assertRaisesRegex(ValueError,'Installed content changed'): configure(root)
            self.assertEqual(before,{p:p.read_bytes() for p in before})
        with self.assertRaisesRegex(ValueError,'recipe changed'):
            add_recipes('Version = 1\n253.craft = 458,469,1,0,0,0,0,0,0\n')


if __name__ == '__main__': unittest.main()
