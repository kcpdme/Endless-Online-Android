# Server-to-client feature gaps

**Implementation update: v0.40.0 addresses all 15 numbered gaps below.**
See [the completion guide](FEATURE_COMPLETION.md) for screens, quest provenance,
validation and rollout details. The remainder preserves the original audit.

Reviewed 24 October 2026 against v0.39.9, commit `5627cab`.

This is a development backlog, based on native etheos handlers, the Python
gateway, Godot interaction routes, imported content, and existing validation
reports. A native handler establishes backend support; it does not establish
that its entire flow works in the phone app. No gameplay changes were made during that audit.

Read-only checks against the hosted server confirmed that `gateway.py`,
`live_session.py`, `skills.py`, and `eo_stats.py` match the reviewed local source.
Live NPC definitions, quest dialogue references and map PK/effect flags were
also checked. Packet probes below used an isolated in-memory session fixture,
not an attack, transaction or mutation in the live world.

**Fix these integration gaps first**

1. **HP/TP drain synchronization — confirmed missing.** Native maps can reduce
   health or mana without an attack. `Map::TimedDrains` sends HP drain through
   Effect_Target_Other `(31,31)` and TP drain through Effect_Spec `(31,16)`, type
   1. The gateway does not decode either. A probe starting at HP 50/TP 20 retained
   those values after native-format updates reporting HP 45/TP 17. This can leave
   bars and skill eligibility stale until another supported packet updates them.
   Live HP-drain maps: 229, 230, 231, 251, 255, 256, 282. Live TP-drain maps:
   **136 Hall of Pain**, 237. Add authoritative decoding, peer feedback, and live
   native tests. Sources: native `src/map.cpp:2644`; `server/eo_stats.py:24`;
   `server/live_session.py:171`.

2. **Normal PvP/PK combat — partial.** The native world implements melee PK and
   player-targeted offensive spells. The gateway ignores Avatar_Reply `(23,3)`
   and Avatar_Admin `(23,17)` damage notifications. Both probes produced only
   generic packet events. Recover packets can still update a victim's HP; this
   does not provide complete damage, hit, death or observer feedback. The client
   also targets offensive spells only at monsters, and the gateway admits
   player targets only for friendly healing. Live PK-flagged maps are **245 and
   277 Wraith Room**; client map JSON omits the PK flag. Finish damage decoding,
   legal player targeting, map metadata and native two-player tests. Existing
   timed arena rounds are a separate, already implemented system. Sources:
   native `src/map.cpp:1468`, `:2065`; `server/skills.py:56`;
   `client/scripts/skills_controller.gd:180`; `tools/import_eo.py:77`.

**Native services/actions without a complete phone flow**

3. **Stat and skill reset at a skill master.** Native StatSkill_Junk resets all
   six attributes, clears learned spells, and refunds level-based points. The app
   supports learning, forgetting individual spells and training, but no full
   reset operation, confirmation, response decoding or shortcut reconciliation.
   Source: native `src/handlers/StatSkill.cpp:227`, `src/character.cpp:1830`;
   `server/skills.py:130`; `client/scripts/skills_controller.gd`.

4. **Marriage approval, wedding and divorce.** Law Bob (NPC 115, map 157) and
   Priest (NPC 114, maps 15, 30, 219) have native handlers, including payment,
   partner checks, outfits and ceremony responses. NPC types 12 and 13 are absent
   from the client's service dispatch, and there are no gateway operations or
   dialogs. Sources: native `src/handlers/Marriage.cpp:25`, `Priest.cpp:26`;
   `client/scripts/online_controller.gd:1225`.

5. **Town message boards.** Native opening, post lists, reading, posting and
   admin moderation exist. The app has no board tile interaction, gateway
   operations or UI. Board tiles already exist on maps 5, 228, 48, 46, 13, 21,
   161 and 151. Sources: native `src/handlers/Board.cpp:25`;
   `client/scripts/online_controller.gd:1178`, `:1215`.

6. **Jukebox selection and shared music.** Native jukebox Open/Msg supports
   paid song selection, protection timers and map-wide track changes. The app
   has map music and a working Bard instrument flow, but no jukebox tile dialog,
   purchase operation or native jukebox-track handling. Jukebox tiles exist on
   maps 14, 106 and 218. Source: native `src/handlers/Jukebox.cpp:26`;
   `server/gateway.py`; `client/scripts/map_music.gd`.

7. **Delete a character.** Native Character_Take/Remove implements a deletion
   handshake and returns the remaining character list. Login selection and new
   character creation exist; deletion has no gateway or client flow. A future
   implementation needs explicit character identification and confirmation.
   Source: native `src/handlers/Character.cpp:118`, `:183`;
   `client/scripts/character_flow.gd`; `server/gateway.py`.

8. **Change account password in the app.** Native Account_Agree implements a
   password change from the character menu. The app supports login, account
   creation and secure saved credentials, but no change-password screen or
   gateway operation. Operator password recovery exists separately. A new flow
   must update/forget saved credentials and invalidate old reconnect proofs.
   Source: native `src/handlers/Account.cpp:154`; `server/reset_password.py`;
   `client/scripts/character_flow.gd`.

9. **Manual emote picker.** Native Emote_Report accepts player emotes. Incoming
   emotes and automatic Fairy Soda emotes are already rendered, but no player
   emote operation or selection UI exists. Source: native
   `src/handlers/Emote.cpp:16`; `server/consumables.py:poll_drunk`;
   `server/live_session.py:249`.

10. **Whisper privacy toggle.** Native Global_Player/Remove disables/enables
    incoming whispers. Whispers themselves work, but there is no setting or
    gateway operation for this preference. Source: native
    `src/handlers/Global.cpp:15`; `server/services.py:215`.

11. **Character book / another player's completed quests.** Equipment inspection
    and the player's own quest journal exist. Native Book_Request additionally
    returns a target's profile and visible completed quests, but is not exposed.
    Source: native `src/handlers/Book.cpp:22`; `server/services.py:inspect_player`.

12. **Talk to an admin / report a player.** Native AdminInteract supports help
    requests and reports, including native admin delivery/report storage paths.
    No user reporting dialog or gateway operation exists. Sources: native
    `src/handlers/AdminInteract.cpp:20`; `server/gateway.py`.

13. **Find a player.** Native Players_Accept distinguishes nearby, online on
    another map, and unavailable. The existing online roster and whispers work;
    the dedicated find request/result is not exposed. Source: native
    `src/handlers/Players.cpp:25`; `client/scripts/chat_window.gd:467`.

14. **Earthquake feedback.** Native Effect_Use `(31,10)` broadcasts quake strength
    and timed quake maps exist, including 119 Apozen and 109 Reaper Cave. The
    gateway probe returned a generic packet; the client handles spike effects
    but no quake event. Add decoding and bounded camera feedback with a suitable
    reduced-motion setting. Sources: native `src/map.cpp:2502`, `:2734`;
    `client/scripts/main.gd:968`.

15. **Ambient NPC speech — conditional gap.** Native NPC::Say broadcasts
    NPC_Player `(26,8)` with `FF FF` prefix, index, message length and text. The
    gateway drops this variant; its probe produced no speech event. Player chat
    bubbles already work. The inspected default speech file has no configured
    speech records, so this is not evidence that every silent NPC is broken.
    Decode/render it when enabling NPC chatter. Quest `AddNpcChat` also remains
    marked TODO in the native quest engine. Sources: native `src/map.cpp:898`,
    `src/npc.cpp:1105`, `src/quest.cpp:89`; `server/live_session.py:263`.

**Content blockers, distinct from missing UI**

- Six live quest NPCs have no AddNpcText/AddNpcInput dialogue for their vendor
  IDs in the active quest files: **Jessica** (NPC 192, vendor 13, map 72),
  **Wolf Leader** (193, vendor 14, map 117), **Pig Farmer** (252, vendor 24,
  map 253), **Prisoner** (300, vendor 53, map 10), **Shady Stefano** (301,
  vendor 54, map 113), **Eddie Matador** (302, vendor 55, map 49). They need
  recovered original scripts or explicitly designed new content, rather than
  another generic dialogue window. The live runtime contains 36 quest files.
- **King/vendor 52 requires content review.** Vendor 52 has no active dialogue
  references, and both live and local NPC 123 currently have combat type 1.
  Older documentation showing it as quest type 15 is stale. Do not blindly
  reclassify it or invent a quest. `King Audience` quest 51 existing does not
  establish vendor-52 dialogue support.
- **Baru Supplies quest 56 is orphaned.** Its dialogue references vendor 56,
  for which the current catalog has no quest NPC definition. The older supplied
  EODelta archive has extra NPCs that were not merged. Its reward text and
  objective/removal logic also need review before enabling it. This is a content
  restoration task, not proof that current quest UI is missing.

**Optional follow-up and maintenance**

- Expand the new Admin panel with bring/go-to-player, moderation, announcements,
  and other selected native tools. Many native admin commands can already be
  sent through admin chat; missing buttons do not mean those commands are absent
  from the server. Native Admin/Announce chat channels also lack dedicated send
  controls.
- Refresh `client/README.md`, `server/README.md` and older missing-content reports.
  They still describe offline-only play, future party/Bard support, or disabled
  Maze Master content. The current source enables quest 17 and repairs its
  cancellation target. Current native role/content definitions take precedence
  over older JSON reports.
- Pets, rebirth and older EODelta extensions are not active etheos features merely
  waiting for a screen. Treat them as separately scoped new server work.
- The enhanced art pilot remains intentionally paused after the requested Classic
  rollback; it is not an unfinished native service integration.

**Already implemented; do not re-add to this backlog**

Online login/account creation, three-character selection and appearance creation,
secure remember/automatic login, reconnect/logout recovery, movement/combat,
equipment and paired slots, shop buy/sell/craft, item use/drop/junk, Gold banking
and locker upgrades, lockers, walking-to-chest opening, chairs, trade, normal
chat/whispers/online list, skill learning/training, self/player/group heals,
party/Bard, Fairy Soda feedback, Guild Bob/guild lifecycle, quest journal,
barber, road signs, inn citizenship/respawn/sleep, native arena notifications and
rounds, rewards, and the initial Admin teleport/item/spawn tools all have current
implementation paths. This audit does not certify every one of those paths
against every item, map, disconnect timing or phone gesture.

Recommended order: HP/TP drains and PK synchronization; skill reset and account
management; marriage, boards and jukebox; remaining social/profile feedback;
then content restoration after obtaining the required scripts/design.
