# Compact chat and two camera views — v0.54.1 (98)

Incoming messages and NPC information reveal the compact feed for **eight seconds after the latest message**. Typing or holding a scroll gesture extends the timer. When it expires, the feed and its hit area disappear; the composer stays available. Full Conversations keeps the session history and stays open when opened manually. Unsent drafts survive collapsing the feed.

A **small down chevron** above the upper-right edge hides the feed immediately. It has a 30×30 touch target, no circular background and no dedicated text column. The original 480-pixel message width is restored. The compact feed uses a slim scroll indicator; modal lists retain their wider touch scrollbars. Native and synthetic pointer events are consumed through release so hiding the arrow cannot turn the same gesture into a walk, attack or NPC interaction. Focus loss clears pointer ownership.

The top **magnifier** switches between exactly two views: **Normal** (the original ×1.65 camera) and **125%** (×2.0625). Its selected state and plus/minus glyph indicate the current view. The preference is stored in `graphics.cfg` alongside, and without replacing, the existing artwork preferences. New devices start at Normal. The icon is available during play, respects open dialogs and sits clear of the other top controls, including admin and summoner pet controls. World targeting uses the camera's updated inverse transform. Existing supported magnify events resolve to the same two modes; this release uses the requested icon option and does not enable or integrate the raw Android pinch pilot.

The signed APK grows by just 33,493 bytes (32.7 KiB) over v0.53.0. Imported textures and native libraries compare unchanged. The existing enhanced artwork is retained. No 4× sample textures or other new raster art is added, and no server/gameplay data changes are required.

Verification is recorded in `docs/chat-zoom-report.json`:

- **75 offline rendered checks** cover NPC/global/system messages, timeout and reading/typing protection, manual collapse, history and draft preservation, real mouse and native/emulated touch ownership, focus loss, two zoom values, preference persistence, correct world-coordinate conversion and layout at 960×540, 1280×720 and 1544×720. No gameplay/network requests are sent by this test.
- **6,120 existing camera checks** plus **2,046 checks specifically at ×2.0625** pass, across 84 source/zoom/display-scale cases. The existing camera shimmer correction is preserved.
- **38 movement checks**, **13 modal scrolling checks** and the rendered emote checks pass.
- Godot import/runtime checks and the signed Android export pass. APK signature, 16 KiB ZIP alignment, installed version/hash and app-data preservation are verified separately in the report.

Tests use in-memory characters and a capture transport, with isolated user data. No live characters are moved, attacked or used for chat posts. Device verification is limited to installing the exact signed package; the phone was in another application, so its foreground task is left alone.

Local captures are under `work/chat-zoom/`: `normal-message.png`, `zoomed-1544x720.png`, `collapsed-1544x720.png`, and matching 960×540 / 1280×720 views. Generated EO artwork and APKs remain ignored by Git. Run the focused regression with a real display:

```bash
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/chat-zoom/userdata" \
  XDG_CONFIG_HOME="$PWD/work/chat-zoom/config" ASTER_VALE_CHAT_ZOOM_OUTPUT="$PWD/work/chat-zoom" \
  work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy \
  --path client --script res://tests/chat_zoom.gd
```

`client/tests/world_sampling.gd -- --zoom-125-only` runs the added camera scale in isolation; the default matrix now includes it alongside the earlier zoom values. `python3 scripts/build.py android --release --toolchain work/toolchain` produces the signed update.
