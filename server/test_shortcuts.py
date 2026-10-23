"""Character isolation, durable saves, native validation and gateway auth boundary."""
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from eo_session import EOError
from shortcuts import ShortcutStore
from gateway import Handler


def session(account='account', name='hero'):
    return SimpleNamespace(shortcut_account=account, state={'self': {'name': name}}, spells=[{'id': 1}, {'id': 5}], trade=None)


class ShortcutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'shortcuts.sqlite3'
        self.store = ShortcutStore(self.path)
        self.s = session()
        self.definitions = patch('shortcuts.item_definitions', return_value={4: {'type': 3}, 331: {'type': 3}, 375: {'type': 3}, 18: {'type': 4}, 6: {'type': 6}, 360: {'type': 10}})
        self.definitions.start()

    def tearDown(self):
        self.definitions.stop()
        self.temp.cleanup()

    def test_no_saved_row_distinct_from_explicitly_empty_slots(self):
        self.assertEqual(self.store.read(self.s), {})
        self.store.write(self.s, 'skills', 0, 0)
        self.assertEqual(ShortcutStore(self.path).read(self.s), {'skills': [0, 0]})

    def test_all_four_survive_store_restart_and_changing_native_login_id(self):
        self.store.write(self.s, 'items', 375, 331)
        self.store.write(self.s, 'skills', 5, 1)
        self.s.character_id = 999
        self.assertEqual(ShortcutStore(self.path).read(self.s), {'items': [375, 331], 'skills': [5, 1]})

    def test_partial_group_save_preserves_other_group(self):
        self.store.write(self.s, 'skills', 5, 1)
        self.store.write(self.s, 'items', 18, 6)
        self.store.write(self.s, 'items', 0, 331)
        self.assertEqual(self.store.read(self.s), {'skills': [5, 1], 'items': [0, 331]})

    def test_account_and_character_scoping_and_case_normalization(self):
        self.store.write(self.s, 'items', 331, 375)
        self.assertEqual(self.store.read(session(name='HERO')), {'items': [331, 375]})
        for other in (session(name='other'), session(account='other')):
            self.assertEqual(self.store.read(other), {})
            self.store.write(other, 'items', 4, 0)
        self.assertEqual(self.store.read(self.s), {'items': [331, 375]})

    def test_depleted_items_bind_without_mutating_inventory_or_learning_spells(self):
        self.s.inventory = []
        self.store.write(self.s, 'items', 331, 375)
        self.assertEqual(self.s.inventory, [])
        self.assertEqual(self.s.spells, [{'id': 1}, {'id': 5}])

    def test_bad_assignments_leave_previous_choices_intact(self):
        self.store.write(self.s, 'items', 4, 0)
        for kind, a, b in [('items', -1, 0), ('items', True, 0), ('items', '4', 0), ('items', 4.0, 0), ('items', 64009, 0), ('items', 360, 0), ('items', 999, 0), ('skills', 99, 0), ('bad', 0, 0)]:
            with self.subTest(kind=kind, a=a):
                with self.assertRaises(EOError):
                    self.store.write(self.s, kind, a, b)
        self.assertEqual(self.store.read(self.s), {'items': [4, 0]})

    def test_requires_authenticated_account_and_native_entered_character(self):
        for s in (session(account=''), session(name=''), SimpleNamespace(state=None)):
            with self.assertRaises(EOError): self.store.read(s)
            with self.assertRaises(EOError): self.store.write(s, 'items', 4, 0)

    def test_gateway_ignores_client_supplied_account_character_and_uses_native_session(self):
        h = object.__new__(Handler)
        h.session = self.s
        h.server = SimpleNamespace(shortcuts=self.store)
        result = h.execute({'op': 'shortcuts_set', 'kind': 'skills', 'first': 5, 'second': 1, 'username': 'victim', 'name': 'victim', 'character_id': 42})
        self.assertEqual(result, {'kind': 'skills', 'slots': [5, 1]})
        self.assertEqual(self.store.read(session('victim', 'victim')), {})
        self.assertEqual(self.store.read(self.s), {'skills': [5, 1]})

if __name__ == '__main__': unittest.main()
