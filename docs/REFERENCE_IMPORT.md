# Supplied resource archives

The two supplied Google Drive downloads are stored locally under `reference/`,
which is ignored by Git. ZIP integrity and extraction paths were checked before
inspection. Historical executables, DLLs and objects were not executed.

| Download | Local filename | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `13vJxH6-5-GVSBCBoAk06io7h1ucrUsoH` | `trunk-305-EODelta.zip` | 28,014,804 | `9632915119cc64d4d21f6ef11a202624950d7f9a0dbdf0f0a904a83a98e6d603` |
| `1ZnCiaBcKPEeeYMAvvxPQrnHLS0FbKmDt` | `gfx.zip` | 9,904,258 | `1b52ed6eec6f7079309eb04dda5aa39002eea3ea4ff84626fab73c390410731f` |

The graphics archive contains all 25 `gfx001.egf`–`gfx025.egf` containers.
They match the previously imported classic client graphics byte for byte.

EODelta is an older EOSERV-derived C++ fork, with historical source changes
for pets, rebirth, arena/PK systems, events, commands and configurable gameplay.
Its source is useful implementation reference. Its bundled data contains only
three numbered maps (`00000`–`00002`), four PUB definition files and two quests;
it is not a complete replacement for the existing 282-map world.

The EODelta PUB files contain 491 items and 304 NPC definitions. All shared
definitions match the current runtime. The additions are item 491, Baru Flock,
and NPCs 303–304, Baru sheppherd (daily) and Baru Tailor. They are not merged into
the running world without the corresponding gameplay/content design.

The current runtime therefore retains the pinned modern `etheos` server and its
world data. The original binary game protocol is translated by a local Python
adapter for the Android client. Runtime PUB definitions supply the client item
and NPC catalog, so the client does not assume that classic client item IDs or
stats match the running server.

Reference archives, generated original artwork, historical databases/configs,
and runtime account data remain outside the public source repository.
The availability of these downloads does not establish redistribution rights
for original game content; upstream source licenses are separate from art rights.
