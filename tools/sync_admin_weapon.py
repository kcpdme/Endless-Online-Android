#!/usr/bin/env python3
"""Sync the already-installed operator weapon into the ignored client catalog."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'server'))
from admin_weapon import ITEM_ID, patch_weapon
from export_catalog import parse_items


def sync(eif, catalog_path):
    data = eif.read_bytes()
    _, changed = patch_weapon(data)
    if changed: raise ValueError('Apply the native admin weapon definition before exporting its catalog')
    item = parse_items(data)[str(ITEM_ID)]
    catalog = json.loads(catalog_path.read_text())
    catalog['items'][str(ITEM_ID)] = item
    catalog['source']['files']['items']['sha256'] = hashlib.sha256(data).hexdigest()
    pending = catalog_path.with_suffix('.pending.json')
    pending.write_text(json.dumps(catalog, indent=2)+'\n'); pending.replace(catalog_path)
    return item


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--eif', type=Path, required=True)
    p.add_argument('--catalog', type=Path, default=Path(__file__).resolve().parents[1]/'client/content/catalog.json')
    a = p.parse_args(); print(json.dumps(sync(a.eif, a.catalog), indent=2))
