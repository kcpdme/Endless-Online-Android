# Classic basic attack cadence — Android 0.58.2

The later [Dragon Warrior / Archer server update](DRAGON_WARRIOR_AND_ARCHER.md)
also restores full bow impact. This document records the earlier cadence-only change.

The November 5, 2026 correction removes bow-specific and target-distance speed
bonuses, and slows ordinary basic attacks to the full classic reference cycle.
The native world enforces a 600 ms minimum between basic attacks for every class.
The client uses 620 ms, retaining a small scheduling allowance. Attack animation
poses remain 120 ms each; their 480 ms active animation has a recovery interval
before another attack. Spells and pet attack intervals are separate rules.

## Reference comparison

The pinned open-source EndlessClient reference at
`d4764cb8b1bad6501c33f38a596d80d3d79c47bb` defines
[12 ten-millisecond ticks per attack phase](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EndlessClient/Rendering/Character/CharacterAnimator.cs#L26).
Its [attack-frame transition](https://github.com/ethanmoffat/EndlessClient/blob/d4764cb8b1bad6501c33f38a596d80d3d79c47bb/EOLib/Domain/Extensions/CharacterRenderPropertiesExtensions.cs#L63)
cycles through five phases and returns to standing on zero. The control handler
waits for standing before the next basic attack. This establishes a 600 ms full
cycle in that client reference. The earlier 500 ms emulator packet limit was a
server minimum, rather than the complete client cycle. This comparison uses the
classic EO-compatible client source, not the private modern EO server source.

Our previous ordinary attacks used a 500 ms native cooldown and 520 ms client
interval. Scav and Dawn used approximately 333 ms at range and 250 ms within two
tiles, with client intervals of 347 and 260 ms. These were custom balance bonuses.
They no longer apply to any bow, distance, target type or player class.

## Implementation

`Character::BasicAttackSeconds()` returns 0.6. The native wall-clock check is
unconditional, including when optional combat-progression rules are disabled.
Changing equipment, facing or timestamp values cannot reset that deadline. The
short packet dispatch interval remains separate, preserving responsive pickup,
turning and movement without reinstating the old shared action backlog.

The adapter advertises 0.62 for both former near/far cadence fields and zero for
the former close-bonus radius, even with a stale old profile. Its protocol ticks
now reflect the advertised interval. The new client also refuses metadata that
would shorten its basic interval, and respects a longer advertised interval.

All seven bow definitions now advertise normal speed; range and per-shot impact
remain unchanged. The targeted runtime migration removes obsolete close-speed
keys, updates the Archer's Marksmanship description and records the new cadence
in the profile. The item detail UI no longer advertises faster firing. No PUB,
map, reward, spell or player-account data is rewritten by this migration.

## Verification

Actual native damage packets were timed under deliberately forged timestamps
and 25 attack requests per second. The suite covers ordinary classes, all seven
bows adjacent and farther away, the former two-tile bonus and disabled optional
progression rules: 24 cases passed. The previous binary fails the corresponding
minimum-interval checks. With progression disabled, its slower shared queue is
also subject to the new wall-clock limit.

| Actual damage intervals | Before | After |
| --- | ---: | ---: |
| Ordinary basic attacks | about 500 ms | about 600 ms |
| Scav/Dawn at range | about 350 ms | about 600 ms |
| Scav/Dawn adjacent or two tiles away | about 250 ms | about 600 ms |

The client held-attack test measured a 620 ms mean interval. Seventeen existing
combat/movement cases, 145 adapter state tests, targeted metadata/migration tests,
32 turn-first input cases and the 21-case pet/collision/backlog regression passed.
The 24 native cases also passed on the hosted machine against a disposable copy
of the deployed runtime. Native build and all 29 patches were checked against the
pinned source. Detailed
local receipts are under `work/attack-cadence-v582/`.

The signed APK is version 0.58.2/code 108. It was installed through ADB, checked
byte-for-byte, and retained the original installation timestamp and app data.

Deployment backed up the old binary, modules, runtime metadata, private config
and stopped-world SQLite database. It updated attack configuration/profile data
and the adapter together; the world, gateway and WebSocket services passed health
checks. The migration preserves file ownership and permissions during atomic replacement,
including the service user's mode-0600 private config. That root-run migration case
is covered by a regression. Public WSS registration, login, character entry, live
cadence metadata and strike receipt passed against the deployed services.
Updating the APK is required for the matching client cadence; native
limits apply to older clients too.
