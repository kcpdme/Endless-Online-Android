# Inn citizenship and respawn

Talk to the innkeeper and choose **Citizenship · Set respawn here**. Answer the
three original town questions, then choose **Register · Set respawn**. The
confirmed town, map and coordinates appear under **Current respawn**. Incorrect
answers keep the form open. Registration is free and never spends sleep Gold.

All five original inns work: Aeven, Estaq, Anundo, Halowdale and Centaur. The
native `CitizenSubscribeAnytime` setting is enabled, so answering another town's
questions replaces the previous citizenship. **Give up citizenship…** requires
confirmation at the current town's inn and returns to the existing default home.

**Sleep** still requests a native price before payment, restores HP and TP, and
warps to the original bed location. Fully rested characters see that status.
Sleeping and citizenship are separate actions.

The gateway sends the original Citizen Open/Reply/Remove packets; the native
server checks the answers and owns the character's home. A self Paperdoll query
confirms the effective home after registration/removal. The gateway never writes
character homes to the database or sends the answer key to the client. Public
respawn metadata comes from the same configured native HomeFile.

`server/configure_inns.py` changes only the native subscription rule. It preserves
the existing home locations, default Aeven spawn, questions, password settings
and character records. Existing native servers can reload the rule using their
SIGHUP config handler. Gateway changes require its normal service restart.

Validation: `server/test_inn_citizenship_ui.py` creates an isolated runtime and
fresh dev account. The actual Godot UI registers all five towns through WSS,
rejects wrong answers, confirms paid sleep and bed warp, and exercises confirmed
renunciation and Back. Native tests then verify the saved character home after
logout, real NPC death/respawn at Centaur (map 29, 23,25), and persisted removal
back to the default home. No production character is used for these tests.
