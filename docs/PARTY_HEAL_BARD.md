# Native parties, healing, Bard and online login

Updated for version 0.37.0 / Android code 51, same package and release certificate.

## Healing

Friendly normal-target spells previously relied on tapping a ground tile and
could not hit the main character's visible sprite. Admin Heal, Large Heal and
other normal friendly spells now arm world targeting. Tap the skill, then tap
yourself or another player; tapping the same shortcut again cancels selection.
Heal Self still casts immediately. World selection uses player sprite bounds,
prioritizes friendly players over NPCs, and includes the main character's current rendered position. Native player IDs are sent in
Spell_Target_Other; HP and TP change only on native spell/recovery packets.
Targets disappearing or leaving range during the chant cancel cleanly.

Group Heal (3) and Aura (18) were explicitly blocked. They now require native
party membership and use Spell_Target_Group after the original chant. The
adapter decodes the native recipient list, updates only each recipient's own
HP, adopts TP only for the caster and displays effects on each healed player.
An unrelated observer never adopts another player's HP or TP. Empty/full
recipient HP does not invent a target heal. Native party rules determine which
members receive healing (same map) and charge TP once. Self-heal events update
party HP percentages from native effect data even when the native server omits
a separate party-HP packet.

## Party controls

Menu → Party provides nearby-player invitations and join requests, explicit
accept/decline, a native member/leader/level/HP list, party-only chat, leaving,
and leader-only removal. Inspecting another player also offers an invitation.
The UI never claims membership before the native create/list/add packet.
Invitations expire; acceptance rechecks native proximity. Unrelated player IDs
and non-leader removals are rejected. Self-removal uses Leave, which confirms
leader disbanding. Asking to join another party requires leaving the current
party first. Parties follow native lifetime rules; membership is not a new
persistent account setting.

Native Party_Target_Group EXP updates totals and emits EXP feedback. A native
level-up flag applies the configured StatPerLevel/SkillPerLevel point gains and
requests a nonblocking native refresh of level/HP/TP maxima. No primary combat
attributes are synthesized. Native monster-kill testing compares client totals
and points to the saved native character database after disconnect.

## Bard

Bard is a music skill, not an ordinary healing/damage cast. Its shortcut opens
three octaves of twelve notes. Playing requires a learned native Bard skill and
an equipped Harp or Guitar. The adapter sends Jukebox_Use and decodes nearby
Jukebox_Msg broadcasts, retaining native instrument, note and direction.
The sender plays locally, matching the native protocol's omitted sender echo.
A bounded voice pool plays the 36 original `har001..036.wav` and 36 original
`gui001..036.wav` samples. Weapon animation and the original music-note emote
accompany notes. Music and drunk emotes are independent of speech bubbles, so playing
preserves existing chat text and its expiry, including Fairy Soda haze. Invalid
notes, missing skill and unsuitable equipment are rejected.
No spell cooldown, TP deduction or invented support buff is added to Bard.
Original WAV samples remain excluded from Git with other supplied EO assets.

## Online-only entry and character looks

The welcome screen offers online login. Menu has Party and Log out in place of
offline reset/welcome controls. Startup no longer loads a legacy offline save;
logout stops gameplay and closes the native connection. Existing local save
files are not deleted. Internal collision/render fixtures remain for regression
coverage and cannot be entered through product controls.

Full-screen selection always displays three slots, with empty slots opening
full-screen appearance creation. The native account limit prevents a fourth
character. See [character flow](CHARACTER_FLOW.md) for layout and creation checks.

Character cards use the five native login paperdoll graphics (BAHSW), expanded
to the same nine-position appearance record used by world rendering. They keep
the native body, skin, hair style and color and render equipped boots, armor,
helmet, shield and weapon with the existing original layers. Selection sends
the chosen native character ID; a test preview never substitutes item IDs for
graphics or changes equipment.

## Verification

- 161 Python unit tests, including group/target heal timestamps and ownership,
  invite/accept/decline/member/HP decoding, removal authorization, party chat,
  EXP/level-point decoding and Bard skill/instrument/note validation.
- `client/tests/social_mobile.gd`: 59 real-scene UI checks including all ten
  targeted healing spells on self and another player, Heal Self, group cast, Bard keyboard, invitation actions, equipped preview,
  selection/login and logout. Rendered login preview inspected visually.
- `server/test_party_live.py`: four isolated dev characters against actual
  etheos; parties of two/three, chat, group heals affecting members but not an
  outsider, ten normal healing spells, both instruments, kick and disband.
- `server/test_party_ui.py`: actual Godot login card, party invitation/roster,
  world-tap Admin Heal and Large Heal on self and another player, Group Heal
  shortcut and Bard keyboard against native
  sessions.
- `server/test_party_exp_live.py`: actual native monster kill shared by two
  members; EXP, native level-up and stat/skill points checked against the saved
  native database after logout.
- Existing shortcut, joystick startup, movement, combat, guild, equipment,
  audio, gameplay and world checks remain in the regression run.
- `tools/test_sfx.py` verifies all 72 original note sample PCM streams, as well
  as the existing 81 effects and metadata mappings.

Deploy `party.py`, `skills.py`, `services.py`, `live_session.py` and `gateway.py`.
Only the gateway needs a restart; the native world binary, character database,
spell definitions and server configuration remain in place. Compatible older
clients continue to work. Reports alongside this file distinguish local/native,
public, build and device verification.
