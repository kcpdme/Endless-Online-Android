"""Validate the real original PCM files and client metadata (including ID offset)."""
import hashlib,io,json,unittest,wave,zipfile
from pathlib import Path
from export_sfx import read_mappings
ROOT=Path(__file__).resolve().parents[1]
ARCHIVE=ROOT/'work/eoserv-crawl/downloads/EOzipped028.zip'
CLIENT=ROOT/'work/EndlessClient'
@unittest.skipUnless(ARCHIVE.exists() and CLIENT.exists(),'original supplied resources unavailable')
class OriginalSfxTests(unittest.TestCase):
    def test_original_playback_ids(self):
        m=read_mappings(CLIENT)
        self.assertEqual({k:m['names'][k] for k in ['PunchAttack','MeleeWeaponAttack','InventoryPickup','AttackBow','Thunder','Heal']},dict(PunchAttack=10,MeleeWeaponAttack=15,InventoryPickup=20,AttackBow=38,Thunder=50,Heal=43))
        for graphic,expected in [(0,[10]),(4,[15]),(39,[30]),(42,[38]),(49,[44,45,46]),(50,[47,48,49]),(58,[53]),(73,[38])]:self.assertEqual(m['weapons'][str(graphic)],expected)
        for graphic,expected in [(1,31),(10,43),(11,50),(12,0),(24,62)]:self.assertEqual(m['effects'][str(graphic)],expected)
    def test_all_72_original_bard_note_samples(self):
        manifest=json.loads((ROOT/'client/content/manifest.json').read_text())
        with zipfile.ZipFile(ARCHIVE) as archive:
            for instrument,prefix in [('49','har'),('50','gui')]:
                notes=manifest['bard_notes'][instrument];self.assertEqual(len(notes),36)
                for index,note in enumerate(notes,1):
                    self.assertEqual(note['source_member'],f'sfx/{prefix}{index:03}.wav')
                    raw=archive.read(note['source_member']);exported=(ROOT/'client'/note['path'].removeprefix('res://')).read_bytes()
                    self.assertEqual(hashlib.sha256(raw).hexdigest(),note['source_sha256'])
                    with wave.open(io.BytesIO(raw)) as original, wave.open(io.BytesIO(exported)) as result:
                        self.assertEqual(original.readframes(original.getnframes()),result.readframes(result.getnframes()))

    def test_bank_preserves_pcm_and_correct_aliases(self):
        manifest=json.loads((ROOT/'client/content/manifest.json').read_text());bank=manifest['sfx'];self.assertEqual(len(bank),81)
        with zipfile.ZipFile(ARCHIVE) as archive:
            for ident,record in bank.items():
                raw=archive.read(f'sfx/sfx{int(ident):03}.wav');exported=(ROOT/'client'/record['path'].removeprefix('res://')).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(),record['source_sha256']);self.assertEqual(hashlib.sha256(exported).hexdigest(),record['sha256'])
                with wave.open(io.BytesIO(exported)) as audio:
                    self.assertGreater(audio.getnframes(),0);pcm=audio.readframes(audio.getnframes());self.assertGreater(len(set(pcm)),1)
                    self.assertGreater(audio.getframerate(),0);self.assertIn(audio.getsampwidth(),[1,2]);self.assertIn(audio.getnchannels(),[1,2])
                    with wave.open(io.BytesIO(raw)) as original:
                        self.assertEqual(audio.getframerate(),original.getframerate());self.assertEqual(pcm,original.readframes(audio.getnframes()))
        for alias,ident in [('attack',15),('punch',10),('pickup',20)]:self.assertEqual(manifest['sounds'][alias]['path'],bank[str(ident)]['path'])
if __name__=='__main__':unittest.main()
