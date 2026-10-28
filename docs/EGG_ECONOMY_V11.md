# Egg economy — balance profile 11

The Aeven Eggkeeper now buys spare unhatched eggs for 40% of their purchase price. Drop odds apply only to eligible Summoner kills of the configured source monsters.

| Tier | Buy Gold | Sell Gold | Drop chance |
| --- | ---: | ---: | ---: |
| Normal | 100 | 40 | 5% |
| Rare | 6,000 | 2,400 | 2% |
| Epic | 20,000 | 8,000 | 1% |
| Legend | 60,000 | 24,000 | 0.5% |
| Mythic | 100,000 | 40,000 | 0.1% |

All sixteen species keep their established tier, unlock level, pet power and TP upkeep. Eggs remain bound against player trading, dropping and chest sharing. A spare can be sold even after changing away from Summoner. Selling an unhatched spare does not release an already hatched bond. Buyback accepts existing egg stacks, including purchased eggs; the native inventory does not track individual egg provenance. Buying and reselling loses 60% of the price.

Profile 11 changes egg sale metadata and the native Eggkeeper price/drop configurations. Class, spell, NPC, companion and other equipment balance remains identical to profile 10, as does the native executable. Existing characters and pet bonds were preserved. The combat encounter table in the guide is explicitly the existing profile 10 combat result, which still applies to this economy-only update.

## Validation and live rollout

Python suite: 237 tests passed. Isolated native pet suite: 173 checks, covering all sixteen species, purchase/hatching/summoning/upkeep/dismissal/death, 40% spare sales and class-change sale. Godot/native integration: 137 checks, including two-egg purchase, exact 40 Gold Penguin sale and hatching the remaining egg.

The live rollout backed up the runtime before changing five configuration/catalog files. A private configuration initially received the wrong owner; this was corrected to the service account before final acceptance and all three services restarted. Public HTTPS/WSS login and character entry, all sixteen offers and native drop configurations, stack buy/sell in all five tiers, and reconnect persistence then passed using a fresh regular test fixture. No existing player was edited. Machine-readable reports accompany this document.

Enhanced original emotes now sit 16 world pixels closer to the head: the 50-pixel cell bottom is 80 pixels above the ground point, with existing four-frame animation and filtering retained. The rendered emote fixture verifies the revised placement.
