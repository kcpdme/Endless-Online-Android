# Travel checks, 5× EXP and more admin destinations — v0.40.2

Monster EXP is now **500% (5×)**. Item and Gold drops remain **100%**.
The setup defaults match production. Quest rewards and existing character
experience are preserved.

## Boat check

Limbo Desert is an ordinary level-0, keyless map crossing. The supplied map
and quest files contain no quest requirement for it; the
[classic map database](https://apollo-games.com/eoclassic/map.php?map=16)
confirms the level/key settings. Cactus Holiday is a repeatable task offered
by the sailor after arrival. The nearby pirate quests lead to other islands.

A fresh, non-admin test character walked from the port's upper boat deck
through the desert crossing and back on the actual native server binary in
a disposable world. Port–Naqid, Naqid–Port and the level-12 island crossing
also passed. The user independently confirmed the desert boat was working.
Map 16 and its quest behavior are unchanged.

## Confirmed exit repair

A static audit checked all **282 maps and 3,945 warp records** for solid warp
origins, missing maps and invalid/solid landing coordinates. Three warp
origins were solid: Estaq stronghold map 48 at **0,40 / 0,41 / 0,42**. Each
already had a valid, level-0, doorless exit to map 40, but the native walk
handler rejected the Wall spec before it could process that exit.

`server/configure_travel.py` removes only these three contradictory Wall
specs, verifies their exact destination records, and updates the EMF revision.
It preserves every other parsed field, including graphics, NPCs, doors,
levels and warps. Repeated setup is idempotent. The module never opens an
account database. `tools/export_travel.py` exports the matching phone geometry
and catalog identity without altering any graphics.

All three exits failed native walking before the repair and passed after it.
The phone geometry passed 15 checks for touch paths, native move requests
and pending warp confirmation. The static audit now finds **zero solid warp
origins**.

The audit separately flags eight pre-existing out-of-bounds maze destinations
and 211 solid landing records; 173 point to Grocery 0,0.
These are not the same as blocked entrances: some solid landing tiles have
walkable neighbors. This patch does not infer their intended replacements.
The existing client guard continues to reject the eight invalid maze routes.
See `tools/audit_travel.py` and `travel-map-audit-report.json` for the scope.

## Admin teleport menu

The menu now has eight destinations. The five existing presets are retained,
with these additions:

| Menu entry | Map | Landing tile |
| --- | ---: | --- |
| Monkey Island | 271 | 25,54 |
| Pyramid | 229 | 82,112 |
| Admin Room | 21 | 12,6 |

Monkey Island uses the original quest's arrival location. Pyramid uses its
existing entrance landing from Vulture Island. Admin Room is the original
Meeting room, rather than the much larger Admin Zone map. All landing tiles
are in bounds, walkable, and away from portals and NPC spawn centers.

The client renders presets supplied by `admin_open`, so reopening Admin →
Teleport fetches the three new entries without a further APK update. The
existing list scrolls to reach them. Ordinary-player visibility and native
admin rank/duty checks remain in place.

The real Godot → WebSocket → gateway → native world test passed **52 checks**,
including touching all eight destinations, correct native arrival positions,
item/spawn regressions and rejection of forged ordinary-player admin requests.
Four admin unit tests also passed.

## Delivery

The native travel probe passed all eight crossing cases in an isolated world.
The live rollout backed up a consistent stopped world, preserved account
DB bytes during installation, and verified every other map, PUB, shop and
drop file was unchanged. The native binary was unchanged. Public health and
TLS connection checks passed after rollout.

Android **0.40.2 / code 68** was installed as a full signed update on the
connected phone. Installed bytes matched, original first-install identity
was preserved, and launch had no script or fatal errors.

APK SHA-256: `3bc447f5f9a619833ba935753f8ab2cc750e410a0ab48128eadc8e4f132c5621`.

Deployment and sanitized validation reports accompany this document.
