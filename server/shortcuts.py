"""Durable per-character HUD assignments, separate from native character saves."""
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from eo_session import EOError
from services import item_definitions, runtime_path


class ShortcutStore:
    def __init__(self, path=None):
        configured = path or os.environ.get('ASTER_VALE_SHORTCUT_DB')
        self.path = Path(configured) if configured else runtime_path() / 'character-shortcuts.sqlite3'
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.execute('CREATE TABLE IF NOT EXISTS shortcuts (account TEXT NOT NULL, character TEXT NOT NULL, kind TEXT NOT NULL, first INTEGER NOT NULL, second INTEGER NOT NULL, PRIMARY KEY(account, character, kind))')

    @contextmanager
    def connection(self):
        db = None
        try:
            db = sqlite3.connect(self.path, timeout=5)
            with db:
                yield db
        except sqlite3.Error as exc:
            raise EOError('Shortcut server storage is unavailable; retry shortly') from exc
        finally:
            if db is not None:
                db.close()

    @staticmethod
    def identity(session):
        account = getattr(session, 'shortcut_account', '')
        me = (session.state or {}).get('self') or {}
        name = me.get('name', '').strip().lower()
        if not account or not name:
            raise EOError('Sign in and enter your character before saving shortcuts')
        return account, name

    def read(self, session):
        identity = self.identity(session)
        with self.connection() as db:
            rows = db.execute('SELECT kind, first, second FROM shortcuts WHERE account=? AND character=?', identity).fetchall()
        return {kind: [first, second] for kind, first, second in rows}

    def write(self, session, kind, first, second):
        identity = self.identity(session)
        if kind not in ('items', 'skills'):
            raise EOError('Choose item or skill shortcuts')
        if any(type(value) is not int or not 0 <= value <= 64008 for value in (first, second)):
            raise EOError('Invalid shortcut assignment')
        if kind == 'items':
            definitions = item_definitions()
            if any(value and definitions.get(value, {}).get('type') not in (3, 4, 6, 22, 23, 24, 25) for value in (first, second)):
                raise EOError('Only consumable items can be assigned here')
        else:
            known = {spell['id'] for spell in session.spells}
            if any(value and value not in known for value in (first, second)):
                raise EOError('Learn this skill before assigning it')
        # A depleted stack is still a valid binding. Saving never consumes items,
        # teaches spells, or changes the native character database.
        with self.connection() as db:
            db.execute('INSERT INTO shortcuts VALUES (?, ?, ?, ?, ?) ON CONFLICT(account, character, kind) DO UPDATE SET first=excluded.first, second=excluded.second', (*identity, kind, first, second))
        return {'kind': kind, 'slots': [first, second]}
