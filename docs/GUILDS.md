# Native guild services

Version 0.34.0 (Android code 46) completes Guild Bob / Guild Master interaction. Tap the NPC sprite to open the six-tab guild window. Mobile forms scroll and resize above the software keyboard; pending requests disable submission buttons.

## Player flows

- **Look up:** search guild information and members by tag or name.
- **Create:** enter a 2–3 letter tag and a 4–24 letter/spaced name. Invite nearby guildless players to support founding. Their Requests tabs show Accept/Dismiss. The founder sees the supporters and can confirm creation only after native approval. The hosted configuration requires **10 members including the founder and 50,000 Gold**. The adapter does not lower these requirements. Closing the window retains the pending founding session; logging out ends the native session.
- **Join:** enter the guild tag and an authorised recruiter's character name. The recruiter must be on the same map. The recruiter receives the application under Requests and explicitly accepts it. Recruitment charges the guild bank its configured fee (currently 1,000 Gold). Offline/wrong-guild/unqualified recruiters and an insufficient guild bank produce native feedback.
- **Manage:** refresh authoritative membership, deposit Gold, edit the description and nine rank names, change a member's rank, remove members, leave or disband. Available controls follow server permission settings; the server validates every operation again. Founder appointment, membership removal, departure, disbanding and Gold payments require explicit UI confirmation. Rank 0 is founder; ranks 1–9 are configurable. Gold deposits have the original configured minimum and capacity limits. Disbanding removes every member.
- **Requests:** founding support and recruiter applications arrive through native packets even while the guild window is closed. Dismissal clears the local prompt; EO has no native negative-reply packet to notify the applicant. Membership is granted only by a native Guild Create/Agree reply.
- **Guild chat:** sends native Talk Request messages only to the guild. Messages also appear with a Guild prefix in the HUD conversation feed; they never become nearby speech bubbles.

Classic EO accepts restricted text: tags use letters; guild/rank names use letters/spaces; descriptions also accept numbers, `@`, `_`, `-` and `.`. The UI/server report invalid values rather than submitting malformed packets.

## State and protocol

`server/guilds.py` implements native family 39. It reads public guild rules from the runtime config and does not write game/account database rows. The gateway exposes explicit guild operations; arbitrary method dispatch is not used.

Creation Request sends invites, Accept records supporters, and Create finalizes only after native CreateAddConfirm. Joining sends Player, recruiters accept with Use, and the applicant receives Agree. Buy changes inventory only from the returned Gold count. Description/rank changes use Agree; member promotion/demotion uses Rank; removal uses Kick.

The native Leave and Disband handlers have no success packet. A subsequent **self Paperdoll request acts as an ordering barrier**, and the returned guild fields prove whether membership actually changed. Guild information/member lists then supply current rank, bank balance and permissions. The same refresh catches kicks or rank changes made by another player; the original server does not send a distinct membership-change packet to those targets. Use **Refresh my membership** when needed.

Asynchronous invitations, supporter confirmations and applications are parsed while waiting for other native replies. They cannot satisfy an unrelated action's acknowledgement. Map changes discard local invitation/application prompts; movement invalidates the open NPC context. Lookup failures keep the window usable. Mutation timeouts instruct the player to refresh rather than automatically spending/retrying again.

## Verification

- 141 Python server unit tests pass, including malformed payloads, permission checks, async reply ordering, creation/member acknowledgements and inventory receipts.
- `client/tests/guild_mobile.gd` passes 25 checks covering actual sprite/button touches, forms, founding readiness, application IDs, confirmations, keyboard-safe layout, Back and disconnect.
- Real etheos lifecycle: create/support/confirm, unqualified-recruiter rejection, promotion to recruiter, insufficient guild bank, deposit/recruitment charge, description/rank names, promotion/demotion, permission denial, kick, private guild chat, leave and disband pass. The **isolated test runtime uses three founders** to exercise the complete approval sequence with five characters; production retains ten. No player database is copied into the test.

Run the isolated lifecycle against supplied runtime content:

```sh
python3 scripts/verify_guilds_native.py --runtime work/server-build/runtime
```

Evidence: `guild-full-native-report.json`, `guild-full-public-report.json`, `guild-full-deployment-report.json`, and `guild-full-build-report.json`.

Signed release APK export, v2/v3 signature verification and 16 KiB alignment pass. No Android device was connected for installation. Some engine test exits intermittently report the pre-existing two-resource shutdown leak after successful assertions; this is separate from guild protocol behavior.
