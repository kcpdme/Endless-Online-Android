# Connection loss and recovery

Version 0.39.3 fixes the disconnect path that opened login through
`_show_welcome()` and then immediately hid that same panel. It previously left
an empty map screen and stale player data.

Connection loss now stops gameplay, clears the logged-in flag, player/entities,
queued movement, casts, trades, chat and service panels, and closes the transport.
A previously verified account/character gets an opaque reconnect screen. It
retries after 1, 2 and 4 seconds, up to three attempts and at most 30 seconds,
including time spent in the Android background. The user can choose Return to
login or press Android Back at any time. Exhaustion, rejected authentication,
a missing character or no recovery credentials returns directly to full-screen
login. Manual logout never retries.

Recovery uses the verified session's credentials only in memory, bound to the
original server endpoint. It still performs native password authentication;
existing single-use reconnect proofs can retire the old connection. Logout,
cancellation and terminal failure discard the recovery credentials and proof.
Optional Android Keystore saved login retains its existing opt-in behavior.
Nothing writes the recovery password to a local save, report or log.

Native etheos `Character::id` is regenerated on login (`character.cpp` and
`World::GenerateCharacterID`). Recovery locates the same unique character name
within the reauthenticated account, then enters its new native ID. It never
chooses the first slot or another character when the previous one is missing.
A fresh authoritative snapshot and streaming acknowledgement restore play.

When an otherwise idle transport receives no application message for five
seconds it sends a lightweight `ping`. An unanswered ping times out after eight
seconds, detecting silent broken connections without movement or a periodic
full-world refresh. Heartbeats do not block inventory/combat/movement actions.
The gateway heartbeat returns only connection health and requires an existing
native session. Ordinary in-flight requests retain their 20-second timeout;
opening a transport retains its 10-second timeout.

Validation includes 23 scene/state checks: visible login after logout/failure,
stale player cleanup, non-blocking heartbeats, same-name/fresh-ID selection,
three-attempt and wall-clock limits, Android Back, rejection and missing
character handling. Actual rendered recovery/login screens were inspected.

The real Godot → WebSocket → gateway → native etheos test uses a separate
temporary world and fresh dev account. It gracefully stops/restarts the native
process, freezes the WebSocket process to simulate a silent network blackhole,
resumes it, and finally stops all three services permanently. It checks actual
reauthentication, character and inventory preservation, resumed streaming, and
automatic visible login after permanent failure. No operator credentials or
production database are used.

```sh
godot --path client --script res://tests/connection_recovery.gd
python3 server/test_connection_recovery_ui.py --godot /path/to/godot --report /tmp/recovery-report.json
```

The live harness requires the staged local runtime from `server/setup.py` and
free loopback ports 18878–18880. The hosted deployment updates only gateway.py
and restarts gateway/WebSocket services; the native world process, character
rows, config and password salt are not rewritten or restarted. The APK retains
Classic graphics and the admin blade catalog entry.

Version 0.39.4 includes this recovery fix together with optional secure automatic
sign-in. The latest live regression also verifies a fresh game scene signing in
from a saved vault entry and reaching native character selection without typing.
