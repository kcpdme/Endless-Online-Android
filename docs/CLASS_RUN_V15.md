# Class controls and resource rules, profile 15

Android v0.56.0 (101) adds a 68 px auto-attack control beside Emotes and a 68 px Run control beneath Zoom. Zoom and Admin exchange their top-row positions. Summoners alone see the top egg collection control. Smaller landscape layouts lift the combat controls to keep the expanded footer target clear.

Every class walks at ×1. Run grants ×1.25, or ×1.5 for Rogue, and consumes 1.5% maximum TP per second for the entire enabled period, including standing still. Native state controls the displayed preference and movement cadence. TP exhaustion or death disables Run; reconnect starts with Run disabled. The native queue and walk timestamps enforce the active speed. Repeated requests and toggling retain fractional resource debt.

Pets spend maximum-TP percentages every two seconds: Normal 0.5%, Rare 1%, Epic 1.5%, Legend 2%, Mythic 2.5%. Fractional TP accumulates between upkeep ticks. Initial summon costs, attack power, egg prices, drop rates, ownership and the existing cooldown rules remain unchanged. Run and a pet draw from the same native TP pool.

Warrior attribute defence changes from `CON ×0.6` to `CON ×1.2`. Ordinary equipment armour is not multiplied; real shields retain their separate existing ×2 armour bonus.

Only Magicians use area spells. Existing spell IDs are retained when converting other professions' area abilities:

| ID | New ability | Class | Behaviour |
|---|---|---|---|
| 3 | Renewing Touch | Priest | Heal one selected player |
| 18 | Restoration | Priest | Heal one selected player |
| 16 | Sweeping Strike | Warrior | One adjacent target |
| 46 | Crushing Blow | Warrior | One adjacent target |
| 27 | Spirit Crush | Summoner | One target |
| 37 | Focused Volley | Archer | One target within equipped bow range |
| 39 | Dancing Blade | Rogue | One adjacent target |

Single-target power and TP/cast costs replace the old area budgets. Mage spells 14, 21, 25 and 49 retain area damage. Both server and client enforce Mage-only area use, including administrator test characters. All 63 spells receive small vector glyphs, class/tier colours and distinguishing rune marks. Existing suitable native effects remain; missing and converted effects receive bounded animated impacts. Summon/dismiss effects occur on actual cast acknowledgements, rather than periodic upkeep updates. This adds no raster art pack.

Eggs and Hatched Eggs occupy one bag cell with centered, inset artwork. Texture minimum-size handling is configured before sizing, preventing the original image dimensions from stretching the icon outside its cell. Valid saved bag positions remain reusable.

## Upgrade

Apply the complete pinned native patch stack through `server/setup.py`, including `etheos-running-class-v15.patch`, and build on a compatible server host. Install the corresponding adapter modules. With the world stopped, run `configure_class_run.py --runtime RUNTIME --world-stopped`. This targeted, idempotent v14/v15 upgrader preserves maps, NPCs, ordinary rewards, shops, equipment budgets and the character database. Do not replace production with a disposable test runtime.

The production rollout backed up runtime and adapter files, checked expected hashes, stopped services, installed the native binary and adapter, ran the targeted upgrade twice, verified unchanged player database bytes and reward files, and restarted healthy services. The backup supports rollback. Password salt was retained.

## Validation

- 40 Python unit checks.
- 32 native acceptance checks in a disposable database: normal/Run movement timestamps, idle and repeated-enable charging, zero-TP fallback, all five pet upkeep tiers with fractional carry, Warrior defence and shield stacking, target counts for each converted attack and Mage area damage, selected-player Priest healing, and the actual Godot → WebSocket → native Run flow (10 client assertions).
- 229 native pet regression checks: all 16 appearances, purchase/hatch/summon, combat, upkeep, cooldown persistence, ordinary/PK/arena deaths, map travel/logout, owner-bound bonus drops and original rewards.
- 954 rendered HUD, egg and spell-visual checks at 960×540, 1280×720 and 1544×720.
- 483 existing rendered classic-dialog/HUD checks, including modal input protection and auto-attack preference.
- Complete 26-patch native stack reproduced; local and deployment-host builds passed.
- Signed APK export, v2 signature and 16 KiB ZIP alignment verified.
- Full phone update installed v0.56.0 (101); installed APK bytes match the signed release and the original Android install timestamp is preserved.

Reports are beside this document as `class-run-v15-*-report.json`. These checks establish the requested mechanics; they are not proof that every class wins every encounter equally. Broader PvP and party tuning remains empirical.
