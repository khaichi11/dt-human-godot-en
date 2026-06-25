# Build & Deploy (Windows / Linux / macOS)

The project is pure Godot 4.6 + GDScript with only `res://` asset paths, so it
runs and exports unchanged on all three desktop platforms.

## Run from source

Open `project.godot` in Godot 4.6 and press **F5**.

## Export

`export_presets.cfg` ships three presets: **Windows Desktop**, **Linux**,
**macOS**. To build:

1. Editor → **Project → Export…**
2. Install **export templates** once (Editor → *Manage Export Templates*) if not
   present.
3. Select a preset → **Export Project** → output goes to `build/<platform>/`.

Or headless:

```bash
godot --headless --export-release "Windows Desktop" build/windows/OP3DigitalTwin.exe
godot --headless --export-release "Linux"           build/linux/OP3DigitalTwin.x86_64
godot --headless --export-release "macOS"           build/macos/OP3DigitalTwin.zip
```

## What ships

Included: scripts, `scenes/`, `assets/op3_meshes/` (21 OBJ), `assets/fonts`,
`assets/motions.json`, `project.godot`, icon. The export filters exclude the
heavy reference material (`ROBOTIS-OP3*`, `DT-Human`, `*.3mf`, `*.stp`, `*.run`),
which is also git-ignored. A fresh `git clone` + open in Godot is enough to run.

## Notes

- macOS exports are unsigned by default; for distribution add signing/notarizing
  in the preset.
- The app opens fully **offline** (loading screen → dashboard); connecting to a
  robot is optional and done at runtime.
