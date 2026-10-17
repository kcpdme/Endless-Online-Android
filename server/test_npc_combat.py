"""Original combat identity, byte-preserving PUB migration and quest safeguards."""
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile
from configure_npc_combat import patch, records, configure, quest_targets, ORIGINAL_ENF_SHA256
from eo_session import number
ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / 'work/eoserv-crawl/downloads/sample-data.zip'
ORIGINAL = ROOT / 'work/eoserv-crawl/downloads/EOzipped028.zip'


@unittest.skipUnless(SAMPLE.exists() and ORIGINAL.exists(), 'supplied original resources unavailable')
class OriginalCombatTests(unittest.TestCase):
    def setUp(self):
        with zipfile.ZipFile(SAMPLE) as z:
            self.raw = z.read('sample-data/pub/dtn001.enf')
        with zipfile.ZipFile(ORIGINAL) as z:
            self.original = z.read('pub/dtn001.enf')

    def test_all_original_combat_and_protection_roles_match(self):
        updated, changes = patch(self.raw); old = records(self.original); new = records(updated)
        self.assertEqual(hashlib.sha256(self.original).hexdigest(), ORIGINAL_ENF_SHA256)
        self.assertEqual([c['id'] for c in changes], [123, 227])
        for ident in old.keys() & new.keys():
            if old[ident]['type'] in (1, 2) or new[ident]['type'] in (1, 2):
                self.assertEqual(new[ident]['type'], old[ident]['type'], ident)
            else:
                self.assertNotIn(new[ident]['type'], (1, 2))
        self.assertEqual(new[123]['hp'], 13000)
        self.assertEqual(len(new), 302)

    def test_no_stats_graphics_names_or_later_quests_are_rewritten(self):
        updated, _ = patch(self.raw); old = records(self.raw)
        allowed = set(range(3, 7)) | {old[i]['start'] + n for i in (123, 227) for n in (7, 8)}
        self.assertTrue(all(a == b or i in allowed for i, (a, b) in enumerate(zip(self.raw, updated))))
        self.assertEqual(len(updated), len(self.raw))
        self.assertEqual(patch(updated), (updated, []))
        self.assertEqual(records(updated)[28]['type'], 15)  # Drunk keeps later quest dialogue.

    def test_unexpected_identity_or_role_refuses_to_patch(self):
        start = records(self.raw)[123]['start']
        for offset, value in ((0, 2), (7, 6)):
            altered = bytearray(self.raw); altered[start + offset:start + offset + 2] = number(value, 2)
            with self.assertRaises(ValueError):
                patch(altered)

    def test_quest_kill_requirement_cannot_silently_become_protected(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / '00051.eqf'
            p.write_text('// KilledNpcs(15,1)\nrule KilledNpcs(299,1) goto Done')
            self.assertEqual(quest_targets(t, records(self.raw))[0]['npc_id'], 299)
            p.write_text('rule KilledNpcs(15,1) goto Done')
            with self.assertRaises(ValueError):
                quest_targets(t, records(self.raw))

    def test_private_pub_link_is_detached_and_invalid_quest_is_atomic(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t); (p / 'runtime/data/pub').mkdir(parents=True); (p / 'runtime/data/quests').mkdir()
            source = p / 'source.enf'; source.write_bytes(self.raw)
            target = p / 'runtime/data/pub/dtn001.enf'; target.symlink_to(source)
            q = p / 'runtime/data/quests/00001.eqf'; q.write_text('rule KilledNpcs(15,1) goto Done')
            with self.assertRaises(ValueError): configure(p / 'runtime')
            self.assertTrue(target.is_symlink()); self.assertEqual(source.read_bytes(), self.raw)
            q.write_text('rule KilledNpcs(299,1) goto Done'); configure(p / 'runtime')
            self.assertFalse(target.is_symlink()); self.assertEqual(source.read_bytes(), self.raw)
            self.assertEqual(records(target.read_bytes())[123]['type'], 1)


if __name__ == '__main__': unittest.main()
