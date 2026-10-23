# Native haircutter, readable signboards and secure account entry

Version 0.38.0 / Android code 53. Same package and release certificate.

The app opens its opaque full-screen login/create-account page directly. The
world is not rendered until a character enters it; the old welcome dialog is
not part of normal startup. The supplied original GFX1:31 title illustration
appears beside the login form. The engine splash logo is suppressed. Selection
still has three native character slots and full appearance creation. Back from
selection returns to account login. Missing-content errors remain separate.

Android offers an unchecked Remember login option. Credentials are saved only
after a successful native account login, never after rejection or a transport
failure. The encrypted record binds the account to its exact host and port;
changing server/account clears the prefilled password. The password is masked
and transient authentication copies are cleared after success/disconnect.
Forget deletes the encrypted file and its key. Login remains a user action;
remembering credentials does not automatically enter a character.

The first-party Godot Android plugin uses a 256-bit AES key held by
AndroidKeyStore, AES/GCM with a freshly generated IV and authenticated
package/schema data, an atomic ciphertext file in `getNoBackupFilesDir()`, and
Android app-private storage. App backup remains disabled. There is no hardcoded
encryption key, plaintext password file, password logging or desktop plaintext
fallback. Unsupported platforms hide the storage option. Invalid/empty records
are ignored safely. APK and AAB use the Gradle source template so both include
the native plugin; source lives under `platform/android`, not the ignored
Godot-generated template directory.

Babs Haircutter (NPC type 10, native salon map 51) opens through Barber_Open.
The preview supports native styles (including bald) and ten colors, rotation,
and a hat-free view without changing equipment. The quote uses the actual
BarberBase + max(1, level) × BarberStep settings. A Gold confirmation precedes
Barber_Buy. The pinned etheos handler reads style/color directly, without the
session prefix used by some other clients. Only Barber_Agree changes Gold and
hair; nearby Avatar_Agree updates other players. Moving, leaving the map,
missing Gold, invalid appearance and stale service contexts are guarded.

Signboards use the text already stored in the original current-map data, as in
EndlessClient. Their visible artwork and tile get touch targets. The original
title-length boundary separates the heading and body; control characters are
filtered and BBCode stays disabled. Reading opens a scrolling, movement-blocking
panel, requires no server request, and supports Android Back. Armed spells keep
their targeting priority.

Validation:

- 168 Python tests, including native barber requests, price, rejection guards,
  atomic/truncated receipts and no optimistic Gold/appearance changes.
- 150 game-scene checks, including all 130 imported sign texts, actual haircut
  controls and confirmation, full-screen entry, optional save-after-success,
  endpoint binding, Forget and empty/malformed credential records.
- Actual local and hosted native sessions touch Babs, buy a haircut, compare a
  nearby observer, relogin and verify saved hair/Gold, then touch a real Aeven
  sign without movement or a network action (26 checks each).
- The production Java vault runs in a disposable Android test UID on the phone:
  no plaintext in ciphertext, random IVs, restoration after force-stopping the
  process, tamper rejection and key/file removal. The test never reads or
  replaces the game's saved credentials.
- Existing character-selection/creation, quest journal, guild, heal/party/Bard,
  Fairy Soda, shortcuts, joystick, movement, combat, audio and world checks pass.
- Release signature, 16-KiB alignment and full installation bytes are checked.
  The Keystore plugin's actual game-process initialization is checked in logcat.

Native server definitions and existing character records are unchanged by the
deployment. Live fixtures are newly created dev characters. Only the adapter
is updated; the native world is not restarted. Original title artwork remains
excluded from Git and can be re-exported with `tools/export_login.py`.

Implementation references: [Godot Android plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html),
[Android Keystore key generation](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec),
and the supplied EndlessClient `BaseControlSet.cs`, `MapInteractionController.cs`
and pinned etheos `handlers/Barber.cpp`.
