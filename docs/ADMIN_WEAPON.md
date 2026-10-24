# Skylar's Admin Blade

Item **491**, weapon damage **1,000–1,000**, one copy granted to the existing
administrator character **skylar**. It uses the original Ultima Blade inventory
icon and weapon doll graphic 33 for both bodies. Accuracy remains the template's
+4; carrying weight and equipment requirements are zero. Native Lore status
prevents trading, dropping and dropping on death. No shop, craft or drop table
supplies it. The server keeps normal attribute, critical-hit and armor rules;
this is the weapon's intrinsic damage, not an override of every combat result.

The grant adds one item to the bag without equipping it or changing the existing
Scav Bow, other inventory, character attributes, spells, account or password.
The operator utility is separate from the public gateway. Its transaction
records a character/item ledger entry so retrying cannot grant another copy,
even if the blade has been equipped, banked or subsequently removed.

`server/admin_weapon.py` appends the definition before the original EIF eof
record, preserves all existing item record bytes, moves eof to the next ID and
updates the PUB revision/count. It refuses an occupied item ID or a changed
existing admin weapon definition. Run only with the world stopped and a
consistent private database/PUB/config backup. The deploy transaction compares
all existing table rows and permits only Skylar's inventory field to change.

```sh
python3 -m unittest discover -s server -p test_admin_weapon.py -v
python3 server/admin_weapon.py --runtime /path/to/runtime --character skylar --world-stopped
python3 tools/sync_admin_weapon.py --eif /path/to/runtime/data/pub/dat001.eif
```

The native integration used a disposable dev administrator, never Skylar's login:
regular Ultima stats 6–12 became 1,005–1,005 with the admin blade, exactly matching
the item damage difference of +999/+993. A native Rat attack dealt 1,507 after
normal critical-hit calculation. Native drop was refused; equipment and damage
survived a world restart. See `admin-weapon-native-report.json`.

The client test checks the real catalog entry, icon, both bodies' original
weapon poses and Classic mode. APK 0.39.2 / code 58 contains the new item catalog
and excludes every experimental art pack. The original graphics remain active.
The ignored generated catalog can be reproduced using the sync command above.

Live deployment backed up SQLite, PUB and config before stopping services and
applied only the new definition and one-time grant. The world and both adapters
were restarted to load fresh definitions. Reports record the private backup
location, preservation checks, native test and APK identity.
