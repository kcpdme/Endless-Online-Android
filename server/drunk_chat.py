"""Original EndlessClient ChatProcessor.MakeDrunk rules, with bounded expansion."""
import random


def make_drunk(message, rng=None):
    rng = rng or random
    # Match the original insertion walk, including doubled inserted consonants.
    # Bound expansion while processing, as well as at the original 128-char cap.
    chars = list(message); index = 0; iterations = 0
    while index < len(chars) and len(chars) <= 256 and iterations < 1024:
        char = chars[index]; lower = char.lower(); extra = ''
        if lower in 'ea':
            if rng.randrange(100) < 70: extra = 'j'
        elif lower in 'uo':
            if rng.randrange(100) < 70: extra = 'w'
        elif char == 'i':
            if rng.randrange(100) < 40: extra = 'u'
        elif char != ' ' and rng.randrange(100) < 40: extra = char
        if extra: chars.insert(index + 1, extra)
        index += 1; iterations += 1
    chars = ['*' if char.lower() in 'aeiou' and rng.randrange(12) == 6 else char for char in chars]
    result = ''.join(char + ('*hic* ' if char == ' ' and rng.randrange(100) < 30 else '') for char in chars)
    return result[:126] + '..' if len(result) > 128 else result
