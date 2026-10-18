"""Small, documented artwork repairs; native map coordinates and gameplay stay intact."""


def restore_chest_art(world):
    # The supplied Hall of Pain has a working, solid chest but no object at
    # (7,55). Use the same original wooden chest resource as its Turtle chest.
    if world.get('id') != 136:
        return
    tile = (7, 55)
    if not any((s['x'], s['y'], s['spec']) == (*tile, 9) for s in world['tile_specs']):
        raise ValueError('Hall of Pain approach chest identity changed')
    objects = world['layers']['objects']
    if not any((o['x'], o['y']) == tile for o in objects):
        objects.append(dict(x=tile[0], y=tile[1], id=247))
        objects.sort(key=lambda o: (o['y'], o['x']))
    world['visual_repairs'] = [dict(x=7, y=55, layer='objects', graphic=247,
                                    reason='Original chest tile was missing artwork')]
