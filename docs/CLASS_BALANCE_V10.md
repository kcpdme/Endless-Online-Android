# Class balance 10 and Android 0.48.1

The live profile now enforces carrying capacity on movement and trading, applies the requested Magician spell split, and gives Priest its own one-second HP recovery clock. Shared accessories and higher-tier Rogue/Archer outfits have more useful stat choices. Android 0.48.1 (code 86) also replaces the social emote artwork and raises it above the face and nameplate.

## Exact rules

- Magician single-target damage is multiplied by 1.5 after class scaling, spell power and training. Area mastery uses ×1; existing radius falloff and target caps still apply. TP cost and chant time are unchanged.
- Priest and High Priest recover 2% maximum HP every second, rounded down with a minimum of one. Sitting doubles it; PK halves it. This does not accelerate the separate two-second TP recovery timer.
- Weight includes every bag quantity and all 15 worn slots. Exactly at capacity is legal; above capacity prevents walking and player trading. Native checks repeat on trade request, acceptance, adding items and confirmation. Both final inventories must fit. Rejected confirmation clears both agreements and transfers nothing.
- Counts use wide integers, including quantities beyond the protocol's 250-weight display limit. Admin characters use real capacity too. Dropping, junking and locker deposits remain available to recover from excess weight. Bound eggs can be junked, but cannot be dropped or traded.
- Warriors retain doubled shield armour. Archers retain weapon/arrow range, ×1/×1.2/×1.5 firing rates and ×2 Scav/Dawn firing only within two tiles directly ahead. Rogues retain twice-normal walking and conditional rear strikes of ×1.5 or ×2. Movement speed never increases attack speed.
- Summoners retain owner-scaled pets, all five tier multipliers and two-second upkeep. Mythic ×1.5 is per pet hit, not an automatic ×2.5 owner-plus-pet DPS multiplier: ordinary owner attacks and pet attacks have different intervals. TP call/upkeep, accuracy, defence and time reaching the target matter.

## Equipment changes and progression

Nine ordinary accessories now offer small distinct STR/AGI, INT/WIS, CHA, CON, HP and TP choices instead of repeating STR bonuses. They stay common to all classes. Rogue and Archer class bodies at levels 25, 35 and 45 have additional AGI and small damage bonuses so their own clothes remain competitive against common Oron/Baru. Their accuracy/evasion and armour identities remain intact. Male/female partners match.

Summoner CHA attack scaling increases from 0.20 to 0.25, with INT scaling unchanged. Its level-8/15 weapons gain a small early damage edge. Pet power is still derived from current equipped owner attack; no independent additive pet-stat bonus was introduced.

The full audit checks 108 legal, obtainable, weight-valid builds: six classes at levels 1/8/15/25/35/45, each using standard, damage-focused and defence-focused full equipment. It includes both rings, both armlets and both bracers. Optimisation searches each slot repeatedly; it is an outlier search rather than an exhaustive proof of the best possible build. All class damage progressions improve, and all late-game sustained comparisons remain inside the audit's 60%-of-best floor. That floor alone is not a claim of equal practical strength.

See [full equipment audit](class-balance-v10-full-equipment-audit.json) and the [browser balance guide](../outputs/balance-revamp/balance-guide.html), which lists 452 equipment definitions and all 63 spells, including legacy/operator definitions separately from player progression.

## Actual monster fights

The [native encounter report](class-balance-v10-encounter-report.json) records 24 real fights against a 5,200-HP King Wurm-stat arena copy. All players are regular level-45 characters with legal full equipment, untrained skills and normal accuracy/critical formulas. Their native HP, TP, attack, accuracy, evasion and armour must match the equipment model before combat begins, allowing a one-point floating-point truncation difference in accuracy. No production character or account is used.

Four scenarios distinguish standing damage, positioned Rogue rear/Archer close opportunities, normal retaliation, and the same five-Big-Health-Potion allowance for everyone. Owner and pet damage are separated without double counting. Priest healing consumes actual cast time and TP. This simple controller does not kite or repeatedly move behind a live solo opponent. Short fights favour full-TP Magician burst, while ranged movement, group healing and multi-target magic need different scenarios. Mage/Summoner deaths in the no-potion stand-still scenario are recorded, not hidden.

All six kill the stationary target; all six can survive the retaliating target with the equal potion allowance. Rogue rear hits and Archer close firing improve their damage as intended. This supports keeping the distinct class tradeoffs; it does not justify making every class a self-healing stationary tank or promising identical kill times. No further global damage multiplier was added from one randomized encounter sample.

## Emotes

Eleven new SVG expressions render at 192×192 source resolution and display as 40-world-pixel bubbles. Their bottom sits at least 96 world pixels above the character's ground point, clearing the face and the normal nameplate. A small pop animation replaces enlarged low-resolution social sprite frames. The hold-and-slide picker uses the same artwork with linear filtering. The separate original music and soda effects are also raised.

The isolated rendered Godot check verifies all eleven textures and positioning. Existing movement and drink/area GUI tests pass. Android 0.48.1 was fully installed over the same signed package and its installed bytes and version were verified; saved app data and first-install time were preserved.

**Phone test limitation:** the phone was logged into Skylar in a hostile room. Skylar died during UI checking. No successful on-device emote screenshot was captured; the final face/nameplate clearance was verified in an isolated rendered scene. No character reset, inventory migration or database correction was performed to conceal that event. See [phone report](class-balance-v10-phone-report.json).

## Deployment and verification

Profile 10 is deployed with a guarded backup at `/opt/aster-vale/backups/class-balance-v10-20261028T123635Z`; all three services and public HTTPS/WSS checks passed. Repeating the rollout was byte-identical. The release did not migrate accounts or change admin status. The existing test Summoner remains available with its prior equipment and permissions.

- 237 Python unit tests.
- 515 native balance checks, including real client spell previews.
- 34 raw native capacity/trade/Magician/Priest clock checks.
- 60 native range/cadence/movement/shield/recovery checks.
- 140 native pet-tier checks, 134 live pet/UI checks, and 31 owner-pet/retaliation/emote checks.
- 17 client movement/capacity and 20 drink/area GUI checks, plus the new rendered emote check.
- 24 measured encounter scenarios; see the report for outcomes and resource usage.
- Complete 23-patch native reconstruction; signed release and 16-KB alignment checks.
- Public regular-fixture WSS testing of pet purchase/hatching/calling, weight refusal and one-second Priest HP pulses.

The short TP probe observed actual upkeep and recovery; it did not wait for a complete level-50 TP depletion. Combat outcomes are a small randomized sample. Group AoE efficiency, coordinated party backstabs and player-versus-player matchups need broader playtesting before further numerical changes.
