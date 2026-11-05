"""Alternate acquisition for classic Dragon armor; awards the same dropped items."""
import re

NPC_ID = 253
ARMOR_RECIPES = {ident: ((469, 10), (470, 10), (1, 200)) for ident in (458, 459)}


def add_recipes(text):
    version = re.search(r'^Version[ \t]*=[ \t]*(\d+)', text, re.M)
    if not version or int(version[1]) != 1:
        raise ValueError('Expected NPC-indexed shop format Version 1')
    pattern = r'^253\.craft[ \t]*=[ \t]*([^\n]*)$'
    match = re.search(pattern, text, re.M)
    values = [int(n) for n in match[1].split(',')] if match and match[1].strip() else []
    if len(values) % 9:
        raise ValueError('Invalid Dragon Warrior recipe width')
    for ident, ingredients in ARMOR_RECIPES.items():
        recipe = [ident, *[n for pair in (*ingredients, (0, 0)) for n in pair]]
        existing = [values[i:i+9] for i in range(0, len(values), 9) if values[i] == ident]
        if existing and existing != [recipe]:
            raise ValueError('Dragon armor recipe changed; review before replacing')
        if not existing:
            values.extend(recipe)
    line = '253.craft = ' + ','.join(map(str, values))
    return re.sub(pattern, lambda _: line, text, flags=re.M) if match else text.rstrip()+'\n'+line+'\n'
