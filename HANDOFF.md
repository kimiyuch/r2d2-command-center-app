# Handoff: Custom macOS App for the Dreame X50 Ultra Complete

_Written 2026-10-16. Starting point for the project folder; read this first._

## Goal

A native macOS app (SwiftUI) for the Dreame X50 Ultra Complete that is **better to use than the official Dreamehome app**. Same robot features, but a cleaner, faster, Mac-native experience.

No extra hardware: **the app runs on the Mac alone** and talks directly to Dreame's cloud. (Home Assistant was considered and dropped: no always-on device available.) The Mac doesn't need to be on all the time; schedules run on the robot itself.

## What "better than the official app" means

The robot's capabilities are fixed (we can only use what the cloud/robot offers). We improve the **experience**:

- **Menu-bar extra:** status at a glance (state, battery, current room), one click to start/dock.
- **Presets / "routines":** e.g. "Kitchen + dining after dinner, vacuum only, suction high" as a single button.
- **Clean, fast map:** pick rooms directly on the map, no clutter, no ads or upsell.
- **Keyboard shortcuts** and **Shortcuts/Siri** via App Intents ("Clean the kitchen").
- **Useful notifications:** run finished, stuck, tank empty/full, consumable running out, and nothing else.
- **History & statistics** at a glance (area, duration, per room).
- **User's top priority (2026-10-16): shortcuts.** The official app lacks fast, direct actions. Shortcuts are therefore **the core of the app, not an extra**: presets, the menu bar, keyboard shortcuts and Shortcuts/Siri come first.

**Limits:** the robot's initial setup / Wi-Fi pairing, firmware updates and possibly some rarely used settings stay in the official app. Keep it installed.

## Architecture

```
┌──────────────────────────────────────────────┐
│ macOS app (SwiftUI, macOS 15+)               │
│  ┌─────────────┐  ┌───────────────────────┐  │
│  │ UI          │  │ App Intents / Menu bar │  │
│  └──────┬──────┘  └───────────┬───────────┘  │
│         └────────┬────────────┘              │
│         ┌────────▼─────────┐                 │
│         │ RobotService     │  (app-facing    │
│         │ protocol         │   interface)    │
│         └────────┬─────────┘                 │
│         ┌────────▼─────────┐                 │
│         │ DreameCloudClient│  (encapsulated, │
│         │ login, devices,  │   replaceable)  │
│         │ props, actions,  │                 │
│         │ map              │                 │
│         └────────┬─────────┘                 │
└──────────────────┼───────────────────────────┘
                   │ HTTPS (unofficial Dreamehome API)
             ┌─────▼──────┐        ┌────────────┐
             │ Dreame     │ ◄────► │ X50 Ultra  │
             │ cloud      │        └────────────┘
             └────────────┘
```

- **`RobotService`** is the interface the UI uses (status, commands, map, rooms). The UI knows nothing about the protocol, so a mock implementation is possible for UI work and tests, and later possibly a Matter implementation for local basic control.
- **`DreameCloudClient`** encapsulates the entire unofficial protocol. When Dreame changes something, only this part needs fixing.

## Protocol source: `dreame_vacuum`

The community Home Assistant integration https://github.com/Tasshack/dreame-vacuum (Python) has reverse-engineered the Dreamehome cloud protocol. It's our reference for:

- login / token refresh (Dreamehome account, **regions**, e.g. `eu`),
- device list, reading/writing properties and actions (MIoT-style siid/piid/aiid),
- map data: download, decode and render (most complex part: compressed map frames, I-/P-frames),
- room/segment cleaning, dock actions, consumables.

**Port strategy: decided 2026-10-16 → B (Python helper), at least for the cloud transport.**

Findings from reading `protocol.py` (commit `f5b8472`):
- The Dreamehome client uses a **hand-built TLS client** that reproduces the official Android app's TLS handshake (fingerprint). Dreame apparently rejects other clients. `URLSession`/Network.framework can't produce this handshake, so a Swift port would mean rewriting a TLS stack. Not worth it.
- On top of that: obfuscated string table (gzip+base64), MD5 request signing with timestamp, AES-encrypted region header, push updates via **MQTT**.
- ⚠️ The hand-built TLS client **doesn't verify the server certificate**. On a hostile network (public Wi-Fi), the token could be intercepted. Acceptable for home use; note it, and consider certificate pinning in the helper later.

→ Architecture: **SwiftUI app + bundled Python helper** (vendored `dreame_cloud` code). The app talks to the helper over a local interface (e.g. JSON over stdio or a Unix socket); `RobotService` hides that from the UI. Only parts that don't depend on the protocol (map rendering, presets) are written in Swift.

License: **MIT** (checked). Copy LICENSE along with the vendored code and keep attribution (done in `spike/vendor/dreame_cloud/`).

## Phases

**Step 0: Spike (validate first!)**: `spike/dreame_spike.py`
- Python CLI on top of the vendored code: login → device list → status (state, error, battery, suction, mode …) → optional command (`start`, `pause`, `dock`, `stop`, `locate`).
- Password + refresh token in the macOS Keychain (service `dreame-mac`), never in files.
- Setup: `cd spike && /opt/homebrew/bin/python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` (important: arm64 Python from `/opt/homebrew`; the x86 Python in `/usr/local` can't build `cryptography`).
- Status 2026-10-16: transport verified (EU server reachable, deliberately wrong login correctly rejected with `invalid_user`). **Real account works** (EU): robot "R2D2", model `dreame.vacuum.r5048h` (supported in `dreame_vacuum`'s model table), status reads correctly. The cleaning mode (4.23) is a packed value on this model, e.g. `3842` = vacuum only, self-clean 15. Commands (`locate`, `start`, `dock`) work too. **Step 0 complete.**

**Phase 1: MVP, shortcuts first**: *status 2026-10-16: foundation done, presets/App Intents still open*

Done:
- `helper/dreame_helper.py`: JSON-lines bridge (methods `login`, `select`, `status`, `action`, `rooms`, `cleanRooms`); secrets only arrive over stdin. Since 2026-10-16 it uses the **full `dreame` package** (vendored unmodified in `helper/vendor/dreame`, incl. `DreameVacuumDevice`: map decoding, rooms, room cleaning, background updates via MQTT). Extra dependencies: numpy, Pillow, mini-racer. Tested live (read-only: login, status, rooms).
- `app/`: SwiftUI app (generated with XcodeGen from `app/project.yml`): login (password + refresh token in the Keychain, service `digital.jamon.dreamemac`), status window, menu-bar extra, "Robot" menu with keyboard shortcuts (⌘↩ start/pause, ⌘D dock, ⌘. stop, ⌘L locate, ⌘R refresh), polling every 20 s.
- **Presets** (`Preset`: name, rooms, mode, suction, passes; stored as JSON in UserDefaults): section in the window with an editor, buttons in the menu bar, ⌘1–⌘9 in the "Robot" menu.
- **App Intents:** run a preset, start, pause, send home, locate, status. Siri phrase e.g. "Run <preset> with R2D2 Command Center". Intents share `AppModel.shared` and wait for the automatic reconnect.
- Tests (`DreameMacTests`, 15 tests): JSON bridge against `fake_helper.py` (results, errors, restart, timeout), AppModel with `MockRobotService`, status decoding.
- Build/run: `cd app && xcodegen generate && xcodebuild -scheme DreameMac -derivedDataPath build build`, then open `build/Build/Products/Debug/R2D2 Command Center.app`. App name **"R2D2 Command Center"** (since 2026-10-16; Siri alternative name "R2D2"); internally the target/module/bundle id stay `DreameMac` / `digital.jamon.dreamemac`, so Keychain items and presets carry over. Icon: `Assets.xcassets/AppIcon` generated from `Robot.imageset/robot.svg` with `app/tools/render_icon.swift`. Signing: Apple Development, team `3TWRBP96AK`. App Sandbox off (the app starts the helper as a subprocess). The helper path is set at build time via Info.plist (`DreameHelperDirectory` = `$(SRCROOT)/../helper`), so for now the app only runs on this Mac from the repo. Installed in `/Applications/R2D2 Command Center.app` (Release build, copied with `ditto`); after changes, rebuild and copy it again. The helper keeps running from the repo, so don't move the repo.

Still open in Phase 1:
- Status details: water tank, dust bin, mop installed; suction/mop modes as settable controls.
- **Offline handling** (2026-10-16): the robot was briefly unreachable via the cloud (error 80001 "设备可能不在线" = "device may be offline"), even though the cloud's `online` flag sometimes said `true`. The helper therefore reports `robot_offline` both when `online == false` and when connecting fails with `cloud_unreachable`. The app shows an offline state and checks again every 60 s.
- **Room cleaning works live** (2026-10-16): preset "Kitchen after dinner" → room 7 ("Kitchen/Dining Room", renamed in the Dreamehome app), vacuum only. Earlier "wrong room" reports: those runs were started with Start (normal "Cleaning" in the current room), not with the preset (confirmed by the user). Helper log: `~/Library/Logs/R2D2 Command Center/helper.log` (requests + commands sent to the robot + status changes; no login params).
- Room names come from the Dreamehome app (custom names), otherwise from the robot's room-type guess (often wrong). The Dreamehome app numbers rooms differently from the internal segment IDs; always go by names.
- Robot's own Dreamehome "shortcuts" (the log shows `SHORTCUTS GET_COMMANDS`, ids 32/33) could be offered as presets too.
- Time-based ("after dinner"): via macOS Shortcuts automations or the robot's own schedules; not built into the app.
- Optionally global hotkeys.
- **Voice (2026-10-16, parked):** a Shortcuts shortcut named after a phrase ("Die Küche du putzen musst") with "Run Cleaning Preset" works when Siri runs it (preset started once via Siri at 18:29). But Siri on the user's Mac (German (Switzerland), Apple Intelligence beta) is unreliable, and phrases containing "putzen"/"saugen" get routed to Apple Home robot vacuums ("Das Gerät Wohnzimmer reagiert nicht"). Alternatives suggested: a phrase without cleaning verbs, macOS Voice Control custom commands (run shortcut), or a keyboard shortcut. App Shortcut phrases in `RobotShortcuts` are English only.
- Push instead of polling: `dreame_vacuum` uses MQTT (`protocol.connect(message_callback=…)`); helper could forward events.
- Refresh tokens the vendored client renews internally during a long session aren't reported back to the app (password fallback covers it).

**Phase 2: Map & rooms**: *map done 2026-10-16*
- Helper `map`: saved map from `dreame_vacuum` (`selected_map.pixel_type`, flipped, cropped, rotated by `rotation` like the Dreamehome app), turned into a **clean vector floor plan** by `helper/floorplan.py` (OpenCV): rooms grown over unassigned floor until they tile the home, furniture holes < 1.5 m² filled. **All rooms in this home are rectangles** (user, 2026-10-16), so each room is fitted as a rectangle (sides peeled while the outermost row/column is < 50 % room, walls within 30 cm aligned, overlaps given to the room the robot saw more of); fallback to the traced/simplified outline if the rectangle covers < 60 % of the room. Sends per-room outline, area (m²), label point; dock and `status.robot` in the same coordinates. OpenCV adds ~119 MB to the helper environment (matters for bundling; a Swift/Vision port is possible).
- App: `MapView` draws the outlines with `Canvas` (translucent room fills over the floor color, so dark mode works; interior walls as floor-colored lines, exterior walls = the non-shared wall segments, so coinciding edges never leave a seam), names + m², dock and robot; click/hover hit-tests the room polygons (even-odd). Main window is now two panes: map with a selection bar (mode, "Clean", "Save as Preset…") left, status/presets/controls right. The preset editor also has the map. Polls every 5 s while cleaning (the helper answers from its cache).
- **Floor plan editor** (pencil button in the map's bottom-right corner): drag room walls; walls are split into segments (`FloorPlanEditing.segments`): shared stretches get one handle per straight wall that moves every flush wall, transitively (`linkedEdges`); exterior stretches get their own handle that moves only that room's wall; ⌥ detaches; snaps to other rooms' walls (8 pt) or the 5 cm grid; rooms ≥ 20 cm. Corrections are stored per map id in UserDefaults (`FloorPlanStore`, only rooms that differ from the automatic plan) and applied over the helper's plan (`RobotMap.applying`); "Reset" per room or all. Purely visual + click targets; cleaning still goes by room id.
- Not yet: cleaning path, no-go zones/virtual walls, live (uncleaned/cleaned) map during a run, rotating the map in the app.

**Next session: Schedules** (user's wish 2026-10-16: e.g. "Mon 8:00 vacuum all rooms", "Wed 8:00 vacuum + mop all rooms"). Name in the app: **"Schedules"** (not "Task": the robot already reports a "task status"; Dreamehome calls it "Scheduled Cleaning"/"Zeitplan"). Store them **on the robot** so they run with the MacBook closed; don't schedule from the Mac.

What we know (robot property 8.2 `SCHEDULE`, read via `dreame_vacuum`):
```
1-1-08:00-0100110-1-1-16-314572817-0   = Mon Thu Fri 08:00, Customize, all rooms, vacuum
2-1-08:00-0001000-1-0-16-314572866-0   = Wed 08:00, Customize, all rooms, vacuum then mop
```
- Fields (`-`-separated, entries `;`-separated): id, enabled (`1`/`2` on, `3` invalid, presumably `0` off), time, weekdays (7 bits, **Sunday first**), `1` repeating / `0` once, unknown (`1` vs `0`; `dreame_vacuum` calls it map_id but it differs between the two on one map), `16` (probably "Customize"), packed settings (`0x12C00011` vacuum vs `0x12C00042` vacuum then mop; rest unknown), options (`0` = all rooms?).
- Delete: action 8.1 with `SCHEDULE_ID` (8.3) = id (`DreameVacuumDevice.delete_scheduled_task`). Create/edit/toggle: **not implemented in `dreame_vacuum`, not documented anywhere**; probably writing 8.2.

Plan (user agreed, to be done next session):
1. **Write test** (with the user present): write 8.2 back with only the Wednesday schedule disabled, confirm in robot + Dreamehome app, re-enable. Keep the original string above to restore exactly.
2. User creates two sample schedules in the Dreamehome app (all rooms): **"Vacuum and mop"** and **"Mop only"** → read 8.2 to learn those mode codes. (Room-specific schedules would need more samples; later.)
3. Build "Schedules": helper methods (list, set enabled, create/edit, delete) + app UI (list like Dreamehome, toggle, delete, editor with time, weekdays, mode; all rooms).

**Phase 3: Extras**
- Notifications, dock actions (mop wash, drying, auto-empty), consumables, history.

## Risks

- **Unofficial API:** Dreame can change it at any time. Mitigated by the encapsulated client and keeping an eye on `dreame_vacuum` upstream for fixes.
- **Account:** unusual traffic could in theory be noticed by Dreame. Keep request rates moderate (no aggressive polling).
- **Map decoder:** biggest porting effort.

## Optional later: Matter as a local fallback

The X50 Ultra supports Matter 1.4 (basic control only, no map). With an Apple TV/HomePod as a home hub, the robot could be added to Apple Home and controlled locally as a fallback. Not planned for now. → Open question.

## Open questions

- [x] What bothers the user most about the official app? **Shortcuts** (see Phase 1).
- [ ] Which shortcuts exactly? (e.g. room presets, Siri, keyboard, menu bar), with 3–5 concrete examples from everyday use.
- [x] Dreamehome account: region **eu**, email + password login works. Note: the server locks after 5 wrong password attempts; the spike only stores the password in the Keychain after a successful login.
- [ ] Is there an Apple TV / HomePod (for the optional Matter fallback)?
- [ ] Distribution: personal use only (dev build) or notarized?
- [x] `dreame_vacuum` license: MIT, attribution required (done).

## Working agreements for the next session

- In the new project folder: copy in this doc, `git init`, start with the **step 0 spike**.
- Keep `DreameCloudClient` separate from the UI; tests against recorded (anonymized) cloud responses.
- Never commit secrets (account, tokens, device IDs). Use a `.gitignore` for local config.

## References

- dreame_vacuum (protocol reference): https://github.com/Tasshack/dreame-vacuum
- Matter certification of the X50 Ultra (Matter 1.4): https://www.matteralpha.com/dreame/dreame-robot-vacuum-and-mop-p2956
- Dreame product page (2.4 GHz note): https://ca.dreametech.com/products/x50-ultra-robot-vacuum
