# Character screens, world healing and Fairy Soda

Version 0.37.0 / Android code 51. Same package and release certificate.

## Character selection and creation

Login, selection and creation use the available safe area. Selection always
shows three large cards side by side, each with the actual native equipped look,
name and level. A gold border marks the selection. Tap a card, then Enter.
An empty card opens creation. At three characters, the extra Create action is
hidden and both client and native server reject a fourth character.

Creation offers Female/Male body buttons, four native skin choices
(White, Tan, Pale, Orc), twenty hair styles and ten hair colors. Previous/next
arrows and dropdowns change the original native values. Tap the preview or its
turn buttons to view all four directions. Name validation and an in-flight
submission guard prevent invalid or duplicate requests; a native rejection
retains the entered name and appearance. Successful creation selects the new
character. Native starter items and appearance rules remain server-controlled.

Previews preserve the original layer offsets and BAHSW login equipment mapping.
Fitting uses the visible alpha bounds of each layer, avoiding small previews
caused by transparent sprite padding. Layout containers divide available width;
the creation controls scroll when necessary.

## Healing

Normal friendly healing spells arm world selection. Tap the skill and then your
own sprite or another player's sprite. No player-picker modal interrupts this
flow. Tap the skill again to cancel. Heal Self casts immediately; Group Heal and
Aura cast on the native party. HP/TP still change only from native packets.

## Fairy Soda and Bard

Both Fairy Sodas still consume through the native bag action, including at full
HP/TP. Native timers are 25 seconds for Small and 137.5 seconds for Big. The drunk
emote uses the original sheet; hiccups, repeated/starred letters and slurring
come from the gateway's existing original-chat transformation. Hiccups are
random. Emotes play periodically rather than staying continuously above a head.
Nearby chat appears in history and in the overhead speech bubble, with subtle
haze while drunk. The observer receives the same transformed message.

A Bard note previously replaced the current chat-bubble record with a short
music bubble. Music is now an independent original emote, alongside the drunk
emote, preserving speech text, haze and expiry. Logout clears both effects.
No server restart or native world changes are needed for this client update.

## Verification

- 153 touch/layout checks: zero through three characters at four
  landscape sizes, third-card selection, appearance controls, rotations,
  submission guards and native errors. Screens visually inspected.
- Local and public native character-flow tests each create three fresh dev
  characters through the UI, verify appearance, reject a fourth and enter all
  three cards with the correct native IDs (48 checks each).
- 59 social scene checks cover all ten targeted heals on self and another player,
  direct Heal Self, party controls, Group Heal and the Bard keyboard.
- Local/public native UI tests touch Admin Heal and Large Heal on self and a
  nearby player, then cast Group Heal and play Bard through the keyboard.
- Two actual Godot clients locally and on the public server verify Small/Big
  Soda consumption and timers, drunk emotes, matching hiccup/slur text, hazy
  overhead speech, Bard preserving chat and logout cleanup (21 checks each).
- 20 soda/area scene checks include native-only consumption and concurrent
  drunk/music/speech state. Existing creation, shortcut, joystick, movement,
  combat, guild, audio, gameplay and world checks pass; 161 Python tests pass.

The JSON reports alongside this document distinguish local, public, mobile,
build and device checks. Live tests use fresh isolated dev accounts.
