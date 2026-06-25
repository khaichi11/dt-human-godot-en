# Texturing — servo vs. metal

## Automatic split (already done)

The official OP3 meshes are one fused STL per link, but inside most of them the
Dynamixel **servo is a separate shell** from the bracket. `split_servo.py`
detects each servo by its XM-430 signature (~28.5 × 34 × 46.5 mm), splits it out,
and exports each link as a `.glb` with two named objects: **`servo`** and
**`frame`**. These ship in `assets/op3_meshes/` and the twin renders the servo
dark and the frame gun-metal, with the **fault red blink landing only on the
`servo`** object.

Detection uses **two criteria (OR)** so it works on both watertight and open
shells:

- **by volume** — a watertight servo box (~43 000 mm³ enclosed), and
- **by extents** — the bounding box matches the XM-430 (catches open shells whose
  enclosed volume is meaningless).

This finds the servo in **17 / 20 links**. Only the **elbow (`la3`/`ra3`)** and
**knee (`ll4`/`rl4`)** keep their servo fused/fragmented into the bracket and
stay all-frame — split those by hand in Blender if you want them targeted too.

Regenerate (needs `trimesh scipy networkx` in a venv):

```bash
python3 split_servo.py     # reads ROBOTIS-OP3-Common meshes -> assets/op3_meshes/*.glb
```

## Manual / custom painting in Blender (optional)

For finer control (real textures, custom colours, head camera lenses) edit in
Blender. The fused links can be separated and painted once; the twin then uses
your result automatically.

## Why this is the right tool

- Per-component material assignment (servo / bracket / lens) needs face-level
  selection — that is exactly what Blender does and Godot/GDScript cannot.
- Export to **glTF (.glb)** carries the materials with the mesh.

## Workflow (per link)

Source meshes: `ROBOTIS-OP3-Common/op3_description/meshes/*.stl`.

1. **Import** the link STL (e.g. `rl3.stl`) — *File → Import → STL*. Do **not**
   move or rotate it (origin/orientation must match the original).
2. **Scale to metres:** select the object, `S 0.001 ⏎`, then *Object → Apply →
   Scale*. (STL is in mm; the twin works in metres, like the existing `.obj`.)
3. **Separate parts:** Edit Mode (`Tab`) → hover a servo, `L` to select its
   linked faces → `P → Selection`. Repeat so the servo body and the bracket are
   separate objects (or use `P → By Loose Parts` if they are disconnected).
4. **Materials:** give each object a material —
   - *Servo* → black, Metallic ≈ 0.6, Roughness ≈ 0.4
   - *Frame/metal* → silver-gunmetal, Metallic ≈ 0.85, Roughness ≈ 0.35
   - *(head `h2` only)* eye lenses → gold, camera → blue, etc.
5. **Re-join** the link's objects: select all parts of this link, `Ctrl+J`
   (materials are kept per-face). Keep the object's origin at world origin.
6. **Export:** *File → Export → glTF 2.0 (.glb)*, **Selected Objects**, format
   *glTF Binary*. Name it exactly like the link: `rl3.glb`.
7. Put the file in **`assets/op3_meshes/`** next to the `.obj`.

## Edit directly in Blender (.blend — easiest)

Godot 4 can import `.blend` files natively, so you can keep editing in Blender
and the twin updates on reimport — no manual export step.

1. In Godot: *Editor → Editor Settings → FileSystem → Import → Blender* and set
   **Blender Path** to your Blender install (once).
2. Save your painted link as `assets/op3_meshes/<link>.blend` (e.g. `rl3.blend`),
   one Blender file per link, modelled in metres at the original origin.
3. Re-focus Godot → it reimports automatically. Edit in Blender anytime; the
   twin picks up the change.

## How the twin picks it up

`OP3Robot._load_link_resource()` loads, in priority order, **`<link>.blend` →
`<link>.glb` → `<link>.obj`**. For `.blend`/`.glb` it keeps **all sub-objects and
their materials as-is**, so your servo-black / metal-silver paint shows exactly.
Just drop the files in `assets/op3_meshes/` and reopen — no code change.

## Servo health targets only the servo

Name the **servo sub-object `servo`** (any name containing "servo") in each link.
The twin then applies the fault **red blink only to that sub-mesh** — the metal
bracket stays its painted colour. If no `servo`-named object exists, the blink
falls back to the whole link (current `.obj` behaviour).

Notes:
- Keep the same file name and origin as the original link so it aligns in the rig.
- Health (red/amber) is driven by `/dt/servo_health`; the panel row dot always
  shows status regardless of mesh type.

## Quickest path

You don't have to do all 21 at once — paint a few visible links first (torso,
head, thighs); the rest keep the default black until you get to them.

## Auto-split status (which links to check)

The servo/frame split runs automatically for every link (`split_servo.py`, using
the Dynamixel XM-430 size signature ≈ 28.5 × 34 × 46.5 mm, by volume **or**
extents). Result per link — **you do NOT need to check all 21 one-by-one**, only
eyeball the robot and revisit a link if its servo isn't dark where you expect:

| Link | Body part | Servo auto-detected? |
| ---- | --------- | -------------------- |
| body | torso | ✅ servo(s) dark |
| h1 | neck (head_pan) | ✅ servo (whole shell) |
| h2 | head (head_tilt + cam) | ✅ servo dark |
| la1 / ra1 | shoulder-pitch | ✅ servo (whole shell) |
| la2 / ra2 | shoulder-roll + upper arm | ✅ servo dark |
| **la3 / ra3** | **elbow + forearm** | ⚠️ all-frame — servo fused into arm |
| ll1 / rl1 | hip-yaw | ✅ servo (whole shell) |
| ll2 / rl2 | hip-roll | ✅ servo dark |
| ll3 / rl3 | hip-pitch (thigh) | ✅ servo dark |
| **ll4 / rl4** | **knee** | ⚠️ all-frame — 240 fragments |
| ll5 / rl5 | ankle-pitch (shin) | ✅ servo dark |
| ll6 / rl6 | ankle-roll (foot) | ✅ servo dark |

- **✅ (17 links)** — a servo was found and coloured dark; fault-red targets only
  that servo (or the whole shell on the compact single-piece links h1/la1/ll1
  etc., which *are* essentially the servo). Nothing to do.
- **⚠️ elbow (la3/ra3) & knee (ll4/rl4)** — here the servo is fused into the
  forearm (la3/ra3) or fragmented into ~240 shells (ll4/rl4), so auto-split can't
  isolate it cleanly and the link stays all-frame; fault-red falls back to the
  whole link. If you want the servo targeted precisely, redo just these four in
  Blender (separate the servo, name it `servo`, export `.glb`).

So in practice only the **elbow and knee pairs** are worth a manual look; the
other 17 links are correctly split.
