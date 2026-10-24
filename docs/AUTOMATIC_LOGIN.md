# Optional saved and automatic sign-in

On Android, tick **Remember login on this device** to keep the verified account,
password and server endpoint in the existing Android Keystore AES-GCM vault.
Tick **Sign in automatically next time** to sign in on future launches and open
the native character selection screen. Choose a character normally, including
accounts with three slots. Automatic sign-in selects Remember as well.

Both choices are opt-in. A failed native authentication never saves credentials
or enables automatic sign-in. A failed vault write disables the automatic
setting. The separate `user://login_options.cfg` contains only a boolean;
account names, server addresses and passwords remain in the encrypted vault.
There is no plaintext password fallback on desktop or unsupported devices.

Startup tries only once, with the verified saved endpoint and normal native
password authentication. Edits to host, port or username clear the prefilled
password and prevent forwarding it elsewhere. Authentication or connection
failure leaves the visible login form and status message. The existing bounded
retry for a still-closing previous native session remains available.

Manual logout stays at login for that run, even if automatic sign-in is enabled
for next launch. Back cancels an in-progress sign-in. Unchecking automatic
sign-in preserves optional saved credentials; unchecking Remember or choosing
**Forget saved login** removes the vault credentials and disables automatic
sign-in. Existing in-world reconnection remains separate and does not change
these device choices.

Validation: 16 scene checks cover opt-in, verified-login-only persistence,
startup-once, endpoint binding, failure fallback, manual logout, Forget,
disabling automatic login and vault failure. The real native integration uses a
fresh game scene and a test vault interface, signs in without typing, reaches
native character selection, enters the same dev character, and then repeats
real world-restart, silent-stall and permanent-outage recovery tests. The
production Android vault implementation is unchanged; its existing independent
instrumentation covers encryption, tamper rejection, process restart and erasure.

```sh
godot --path client --script res://tests/automatic_login.gd
python3 server/test_connection_recovery_ui.py --godot /path/to/godot --report /tmp/recovery-report.json
```

Version 0.39.4 / code 60 retains Classic graphics, Skylar's Admin Blade and the
connection recovery fix. Signed in-place updates preserve app data and the
Keystore vault; never uninstall or clear app data to apply this update.
