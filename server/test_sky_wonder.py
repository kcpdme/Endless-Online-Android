"""Exact map preservation, safe landings and repeatable sky-route installation."""
import json,shutil,sys,tempfile,unittest
from pathlib import Path
from configure_sky_wonder import repair,configure,ENTRANCES,SKY_EXIT,parse,SIGN_TITLE,SIGN_BODY
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from import_eo import parse_emf
BASE=ROOT/'work/mortal-eggs/runtime'

@unittest.skipUnless((BASE/'data/maps/00073.emf').exists(),'reference maps unavailable')
class SkyWonderTests(unittest.TestCase):
    def world(self,mid):
        raw=(BASE/f'data/maps/{mid:05}.emf').read_bytes();return raw,parse_emf(raw,mid),parse_emf(repair(mid,raw),mid)
    def test_only_reviewed_avenue_gate_and_original_art_are_added(self):
        raw,before,after=self.world(23)
        for key,expected in ENTRANCES.items():
            actual=next(w for w in after['warps'] if (w['x'],w['y'])==key)
            self.assertEqual((actual['map'],*actual['destination'],actual['level'],actual['door']),expected)
        after['warps']=[w for w in after['warps'] if (w['x'],w['y']) not in ENTRANCES]
        points={(12,2),(15,2),(12,4)}
        after['tile_specs']=[s for s in after['tile_specs'] if (s['x'],s['y']) not in points]
        after['blocked']=[v for v in after['blocked'] if tuple(v) not in points]
        after['layers']['objects']=[s for s in after['layers']['objects'] if (s['x'],s['y']) not in points]
        sign=next(s for s in after['signs'] if (s['x'],s['y'])==(12,4))
        self.assertEqual(sign['text'],SIGN_TITLE+SIGN_BODY);self.assertEqual(sign['title_length'],len(SIGN_TITLE))
        after['signs']=[s for s in after['signs'] if (s['x'],s['y'])!=(12,4)]
        self.assertEqual(before,after)
    def test_bridge_and_sky_only_change_the_reviewed_return_destinations(self):
        for mid in [71,73]:
            raw,before,after=self.world(mid)
            if mid==73:self.assertEqual(after['name'],'Sky Wonder Path');after['name']=before['name']
            changed=[]
            for a,b in zip(before['warps'],after['warps']):
                if a!=b:
                    changed.append((a['x'],a['y']));self.assertEqual(b['map'],73 if mid==71 else 23)
                    b.update(a)
            self.assertEqual(set(changed),SKY_EXIT if mid==71 else {(20,11),(20,12)})
            self.assertEqual(before,after)
    def test_repeated_installation_is_byte_identical_and_detaches_reference_symlinks(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t)/'runtime';(r/'data/maps').mkdir(parents=True)
            originals={}
            for mid in [23,71,73]:
                source=Path(t)/f'{mid}.emf';source.write_bytes((BASE/f'data/maps/{mid:05}.emf').read_bytes());originals[mid]=source.read_bytes();(r/f'data/maps/{mid:05}.emf').symlink_to(source)
            first=configure(r);self.assertEqual(first['maps_changed'],[23,71,73]);self.assertFalse(configure(r)['maps_changed'])
            for mid in [23,71,73]:
                self.assertEqual((Path(t)/f'{mid}.emf').read_bytes(),originals[mid]);p=r/f'data/maps/{mid:05}.emf';self.assertFalse(p.is_symlink());self.assertEqual(repair(mid,p.read_bytes()),p.read_bytes())
    def test_conflicting_last_map_causes_no_partial_write(self):
        with tempfile.TemporaryDirectory() as t:
            r=Path(t);(r/'data/maps').mkdir(parents=True)
            for mid in [23,71,73]:shutil.copy2(BASE/f'data/maps/{mid:05}.emf',r/f'data/maps/{mid:05}.emf')
            p=r/'data/maps/00073.emf';raw=bytearray(p.read_bytes());raw[7:31]=b'conflicting-map-identity!';p.write_bytes(raw)
            before={p.name:p.read_bytes() for p in (r/'data/maps').glob('*.emf')}
            with self.assertRaises(ValueError):configure(r)
            self.assertEqual(before,{p.name:p.read_bytes() for p in (r/'data/maps').glob('*.emf')})

if __name__=='__main__':unittest.main()
