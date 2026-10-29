# Mobile zoom feasibility pilot

This is an **opt-in offline prototype**, not a change to normal play. `main.tscn`, the default ×1.65 camera, gameplay controls, installed artwork and phone APK remain unchanged. The prototype lives in `client/tests/zoom_pilot.gd`; it never connects to production accounts. A capture session replaces the network transport, and all runs use isolated user data.

## Findings

Pinch zoom and a one-thumb slider are feasible. Presets compare the current view (100%) with 125%, 130% and 150%, preserving uniform proportions and keeping the player at the camera's center. The experimental range is 90–150%. At 130%, the camera uses ×2.145 and displays about 59% of the map area visible at 100%; larger actors trade some surrounding visibility for readability. HUD elements keep their size.

The recommendation is **125–130% for normal mobile viewing, with an optional 150% close view**. The existing enhanced 2× player art remains usable around 125–130%. A 4× sample looks crisper in some weapon outlines, faces and clothing edges, but its visual advantage is modest and some reconstructed edges look more angular. Automatically increasing resolution does not add newly drawn detail. Selective upgrades are preferable to replacing every asset immediately. Ground, architecture and scenery in these captures retain the original graphics, so their pixel structure becomes more noticeable at stronger zoom.

The higher-resolution sample covers all poses referenced by six class outfits: **1,504 source frames / 328 shared patches**. It reuses the existing private xBRZ 4× working images, restores exact-black hat masks and uses WebP quality 90 with lossless mask images. It does not replace the shipped pack. Its compressed images total 725,792 bytes, versus 597,800 bytes for a separately encoded 2× reference of the same patches. These individual-patch measurements are not an APK-size forecast. Decoded RGBA is 18,602,624 bytes at 4× versus 4,650,656 bytes at 2×: **four times the texture memory**. Normal 2× NPCs and dropped items remain visible in the world comparison.

## Verification and limits

The pilot passes **982 checks**, using Godot's real renderer and a 2,316 × 1,080 offscreen viewport with the phone's 1,544 × 720 logical layout. Captures compare all four zoom presets and 2×/4× artwork across six classes, five animation states and four directions. Godot import and normal runtime checks also pass. Machine-readable results are in `docs/zoom-pilot-report.json`.

Input coverage includes indexed multi-touch, pinch-in/out limits, either-finger release, third-finger cancellation, near-zero spans, cancelled touches, focus loss, modal interruption, duplicated synthetic mouse input, real joystick capture, inventory-button ownership and a native/emulated GUI thumb-slider drag. The first free-world touch waits until release before emitting a tap; once a pinch begins, the whole gesture consumes all remaining releases. This avoids moving or attacking before the second finger arrives. The prototype uses a tap counter instead of dispatching real world actions. Integrating this deferred-tap behavior with NPC selection, spells, click-to-walk and combat still requires a production integration pass.

The normal client has a basic `InputEventMagnifyGesture` handler. [Godot's documentation](https://docs.godotengine.org/en/stable/classes/class_inputeventmagnifygesture.html) explains that Android's built-in magnify gesture requires `input_devices/pointing/android/enable_pan_and_scale_gestures`. The pilot instead classifies raw indexed touches, avoiding a project-wide setting change and allowing control ownership to be tested. It suppresses a magnify event while raw touches own a pinch so a gesture cannot apply zoom twice.

**No Android installation or physical gesture/performance test was performed.** These desktop checks establish the control logic and visual feasibility; they do not establish phone FPS, memory usage, battery cost or pinch feel. The installed v0.53.0 app is untouched. Before rollout, test real two-finger gestures, targeting while zoomed, crowded maps, rotation/resume and low-memory devices. Add preference persistence and a compact final control layout during integration; the large panel in the screenshots is only a comparison tool.

## Run locally

Requires original local content, the previous private `work/player-item-smoothing/` intermediates, Pillow and the configured Godot toolchain. Generated sample art stays under ignored `work/zoom-pilot/`, loaded directly into the opt-in harness; no additional client artwork is imported or packaged.

```bash
mkdir -p work/zoom-pilot
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/zoom-pilot/userdata" \
  XDG_CONFIG_HOME="$PWD/work/zoom-pilot/config" ASTER_VALE_ZOOM_OUTPUT="$PWD/work/zoom-pilot" \
  work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy \
  --path client --script res://tests/zoom_pilot.gd -- --prepare-zoom-art
python3 tools/prepare_zoom_pilot.py
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/zoom-pilot/userdata" \
  XDG_CONFIG_HOME="$PWD/work/zoom-pilot/config" ASTER_VALE_ZOOM_OUTPUT="$PWD/work/zoom-pilot" \
  work/toolchain/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy \
  --path client --script res://tests/zoom_pilot.gd
```

Add `-- --interactive-zoom-pilot` to the last command to keep the offline window open. Drag the slider or press a preset; use two fingers in free world space on a touch-capable display. `H` toggles the sample 4× player layers. Releasing a world tap only increments a test counter; movement/combat are deliberately inert. Close the window to exit. Without private 4× intermediates, the first and last commands can still exercise the controls and current artwork by skipping preparation and the Python step.

Local images are `work/zoom-pilot/world-100.png`, `world-125.png`, `world-130.png`, `world-150.png`, `world-150-4x.png` and `art-<state>-<direction>.png`. They are actual imported/runtime renders, not illustrations. No source or derived EO binary artwork is committed.
