# Platforms: Web, Android, iOS, macOS

Godot 4.7, GL Compatibility renderer, 360x640 portrait viewport (`canvas_items` + `expand`), portrait orientation.
Export presets live in `export_presets.cfg` (Web, Android, macOS). Output goes to `build/` (git-ignored).
Preset key names were checked against the Godot source (`platform/*/export/export_plugin.cpp`); the editor
fills in any missing keys with defaults the first time the Export dialog is opened.

## 1. Export templates (one-time)

Templates are NOT bundled with the editor and are not committed.

1. Open the project in the Godot 4.7 editor.
2. `Editor > Manage Export Templates` > `Download and Install` (must match the exact editor version, 4.7.x).
3. Offline alternative: download the `.tpz` export templates file for your exact version from the official
   site and use `Install From File`.

Templates install to `~/Library/Application Support/Godot/export_templates/<version>/` on macOS.

CLI export (after templates are installed):

```
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-debug "Android" build/android/cyber-scroller.apk
godot --headless --path . --export-release "macOS" build/macos/cyber-scroller.zip
```

## 2. Web

Preset choices (see `export_presets.cfg`):

- `variant/thread_support=false`: single-threaded build, so no SharedArrayBuffer and no COOP/COEP headers.
  Works on itch.io, GitHub Pages and any static host. Single-threaded is also the engine default.
- `variant/extensions_support=false`: GDExtension is not needed.
- VRAM compression: both desktop (S3TC/BPTC) and mobile (ETC2/ASTC) are on, so the build runs on every GPU.
  This makes the pck bigger; trim after testing if size matters.
- `html/canvas_resize_policy=2` (Adaptive): the canvas matches the browser window; the project's stretch mode
  scales the 360x640 viewport (letterboxing is avoided by `expand`: wider screens get more width).
- Default HTML shell, PWA off.

Test locally (browsers refuse `file://`):

```
cd build/web
python3 -m http.server 8060
# open http://localhost:8060/index.html
```

Or use the editor's `Remote Debug > Run in Browser` (needs templates). Open DevTools (F12) for errors.
If you later enable the PWA, a service worker may serve stale builds; unregister it in DevTools.

Hosting: serve `.wasm` as `application/wasm` and `.pck` as `application/octet-stream`, and enable gzip/brotli
(the wasm shrinks to roughly a quarter). On itch.io upload a zip of `build/web` with `index.html` at the root
and mark it "played in browser".

### Web gotchas

- **Audio unlock**: browsers block audio until a user gesture. Start the first sound only after the first
  tap/click/key (for example a "TAP TO START" screen before any music). Since 4.3, web audio defaults to Sample
  playback: low latency but no bus effects. Switch the web playback type to Stream if effects are needed.
  The `Audio` autoload (`scripts/audio/`) keeps Sample playback: it stays silent until the first input, and
  the active-pause music filter is a pre-rendered low-passed copy of each loop crossfaded in sync, not a bus effect.
- **Save data**: `user://` is backed by IndexedDB on web. It persists per origin, can be cleared by the user, and
  is lost in private browsing. Save right after meaningful events (end of mission), not on quit; there is no
  reliable quit hook on web. Consider an export/import save string.
- **Fullscreen**: browsers only allow fullscreen/mouse capture from inside an input event. Call
  `DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)` from `_input`/`_unhandled_input` or a
  Button `pressed` handler, never from a timer or `_ready`.
- **Touch browsers**: `emulate_mouse_from_touch` (default on) keeps mouse-based UI working.
- **Keyboard focus**: `html/focus_canvas_on_start=true` so keyboard input works immediately. In an iframe
  (itch.io) the player must click once first.
- **No threads**: `Thread`/`WorkerThreadPool` degrade to synchronous behavior in single-threaded builds.
- **No OS-level features**: no `OS.execute`, limited file dialogs.

## 3. Android

### Setup (one-time)

1. Install a JDK (the Godot docs name the required version for 4.7; OpenJDK 17 has been the requirement for 4.x),
   e.g. `brew install --cask temurin@17`.
2. Install the Android SDK (Android Studio or the command-line tools) with the packages listed on the official
   "Exporting for Android" page for 4.7 (platform-tools, build-tools, a platform, cmdline-tools, cmake).
3. In the editor: `Editor > Editor Settings > Export > Android`: set `Java SDK Path` and `Android SDK Path`.
   Create a debug keystore if none exists:

```
keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
  -keystore debug.keystore -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
```

   Then set `Debug Keystore` (path), user `androiddebugkey`, password `android` in the same Editor Settings page
   (editor-wide, not stored in the repo).
4. Enable USB debugging on the phone (Developer options), connect, accept the RSA prompt. The one-click deploy
   button (Android icon, top right of the editor) installs and runs the debug build.

### Preset notes

- Orientation is not a preset option in Godot 4: it comes from `display/window/handheld/orientation`
  (value 1 = portrait, already set).
- Architectures: `arm64-v8a` and `armeabi-v7a` on; x86 targets are only for emulators.
- `gradle_build/min_sdk` and `target_sdk` are left empty so Godot's defaults for 4.7 apply. Gradle build is off
  (uses the prebuilt template). Turn it on only for plugins, AAB output, or custom manifest changes.
- `permissions/internet=false`: enable only if online features are added.
- Package: `com.lifecoder.cyberscroller`.
- Release builds need a release keystore (never commit it). Keep keystore passwords out of
  `export_presets.cfg`; use Editor Settings or CI env vars (`GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
  `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`). Google Play needs an AAB,
  which needs the gradle build.
- Provide launcher icons (`launcher_icons/main_192x192` and the 432x432 adaptive layers) before release.

### Android gotchas

- **Safe areas / notches**: `screen/edge_to_edge` is off by default. If you enable it, use
  `DisplayServer.get_display_safe_area()` (a `Rect2i` in screen pixels), convert to viewport coordinates through
  the window/stretch transform, and keep HUD margins at least the insets. Re-query on
  `NOTIFICATION_WM_SIZE_CHANGED`.
- **Touch targets**: aim for 44-48 dp (about 7 mm). On a ~6" 1080p phone one virtual pixel is about 3 physical
  pixels, so dice, hack buttons and other buttons should be at least 24-28 virtual px high with 4+ px gaps.
- **Pause on focus loss**: fights are turn-based, so nothing runs while the app is in the background. The run is
  saved after every step between fights; a run closed mid-fight resumes at the start of that fight.
- **Back button**: handle `NOTIFICATION_WM_GO_BACK_REQUEST`.
- Immersive mode is on (system bars hidden).
- `user://` is app-private storage and is cleared on uninstall (`retain_data_on_uninstall=false`).

## 4. iOS (later)

- Needs macOS, Xcode, an Apple Developer account (free for device testing, paid for TestFlight/App Store), and
  the iOS export template (part of the standard templates).
- Add an "iOS" preset: team ID, bundle identifier (e.g. `com.lifecoder.cyberscroller`), icons, launch screen.
  Orientation comes from the project setting (already portrait).
- Godot exports an Xcode project; build and sign in Xcode. Keep `rendering_method.mobile` at `gl_compatibility`
  (already set).
- Use the simulator to smoke-test layouts and safe areas on notched devices.
- Audio starts only after a touch, like Safari. Safe areas use the same `get_display_safe_area()` API.

## 5. macOS (quick desktop testing)

The preset exports a universal zip with ad-hoc signing (`codesign/codesign=1`), for local testing only. Running
an unsigned build may need `xattr -dr com.apple.quarantine <app>`. Day-to-day testing is faster in the editor.

## 6. Performance notes (GL Compatibility)

- Stay on `gl_compatibility`; it is the renderer that fits web and the widest range of mobile GPUs.
- Texture filter is Nearest (project default); avoid mixing materials to keep canvas batching effective.
- Minimize distinct materials/shaders on CanvasItems; each unique material breaks a batch. Implement the
  scanline/tint overlay as a single full-screen node.
- Avoid `Light2D`, shadows, chained `SubViewport`s and full-screen post-processing on low-end phones (fill rate).
- Prefer a few atlases over many small textures (build `ImageTexture` atlases at startup for procedural sprites).
- Pool projectiles, FX and floating damage numbers instead of bursts of `instantiate`/`queue_free`.
- Shader compile hitches: draw each material once during a loading screen so the first use does not stutter.
- Cap `Engine.max_fps` at 60 on mobile; a 30 fps battery mode is an option. `application/run/low_processor_mode`
  stays off because the game is realtime.
- Profile on a real mid-range phone; desktop Chrome numbers are not representative.
