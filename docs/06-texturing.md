# Texturing the robot in Blender (servo vs. metal)

The official OP3 meshes are **one fused mesh per link** — within `rl3.stl` the
Dynamixel servo and its aluminium bracket are a single object with no material
split. So colouring "servo = black, bracket/metal = silver" cannot be done in
code; the parts must be separated and painted once in Blender. After that the
twin uses your painted result automatically.

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
