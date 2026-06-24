#!/usr/bin/env python3
"""Convert binary STL (mm) -> OBJ (meters) with smoothing-angle normals.

STL has no smoothing info, so we reconstruct it: each face corner's normal is
the average of incident face normals that are within CREASE_ANGLE of that face.
Result: curved surfaces (cylinders/fillets) shade smooth like Fusion, while
sharp edges (box corners) stay crisp. Pure stdlib."""
import struct, sys, os, glob, math

SCALE = 0.001                       # mm -> m (matches URDF mesh scale 0.001)
CREASE_ANGLE = 30.0                 # deg: below this = smooth, above = hard edge
COS_CREASE = math.cos(math.radians(CREASE_ANGLE))


def convert(stl_path, obj_path):
    with open(stl_path, "rb") as f:
        data = f.read()
    (ntri,) = struct.unpack_from("<I", data, 80)
    if 84 + ntri * 50 != len(data):
        raise ValueError(f"{stl_path}: not binary STL")

    verts = []                      # unique positions (x,y,z)
    vmap = {}                       # pos key -> 0-based index
    tri_pi = [None] * ntri          # tri -> (pi0,pi1,pi2)
    tri_n = [None] * ntri           # tri -> UNIT face normal (for crease test)
    tri_area = [0.0] * ntri         # tri -> area (weight for smoothing)
    incid = {}                      # pos index -> list of tri indices

    off = 84
    for t in range(ntri):
        vx = struct.unpack_from("<12f", data, off)  # nx ny nz + 3*(x y z)
        off += 50
        p = []
        pis = []
        for k in range(3):
            x = vx[3 + k*3 + 0] * SCALE
            y = vx[3 + k*3 + 1] * SCALE
            z = vx[3 + k*3 + 2] * SCALE
            p.append((x, y, z))
            key = (round(x, 7), round(y, 7), round(z, 7))
            pi = vmap.get(key)
            if pi is None:
                pi = len(verts)
                verts.append((x, y, z))
                vmap[key] = pi
            pis.append(pi)
            incid.setdefault(pi, []).append(t)
        # face normal via cross product
        ux, uy, uz = (p[1][0]-p[0][0], p[1][1]-p[0][1], p[1][2]-p[0][2])
        wx, wy, wz = (p[2][0]-p[0][0], p[2][1]-p[0][1], p[2][2]-p[0][2])
        nx, ny, nz = (uy*wz-uz*wy, uz*wx-ux*wz, ux*wy-uy*wx)
        ln = math.sqrt(nx*nx + ny*ny + nz*nz)  # = 2 * area
        if ln > 0.0:
            nx, ny, nz = nx/ln, ny/ln, nz/ln
        tri_pi[t] = pis
        tri_n[t] = (nx, ny, nz)
        tri_area[t] = ln * 0.5

    # build per-corner smoothed normals (deduped)
    norms = []
    nmap = {}
    face_lines = []
    for t in range(ntri):
        fn = tri_n[t]
        pis = tri_pi[t]
        nidx = []
        for pi in pis:
            sx = sy = sz = 0.0
            for g in incid[pi]:
                gn = tri_n[g]
                if fn[0]*gn[0] + fn[1]*gn[1] + fn[2]*gn[2] >= COS_CREASE:
                    w = tri_area[g]            # bobot luas: redam sliver
                    sx += gn[0]*w; sy += gn[1]*w; sz += gn[2]*w
            ln = math.sqrt(sx*sx + sy*sy + sz*sz)
            if ln > 0.0:
                sx, sy, sz = sx/ln, sy/ln, sz/ln
            else:
                sx, sy, sz = fn
            nkey = (round(sx, 4), round(sy, 4), round(sz, 4))
            ni = nmap.get(nkey)
            if ni is None:
                ni = len(norms)
                norms.append((sx, sy, sz))
                nmap[nkey] = ni
            nidx.append(ni)
        face_lines.append((pis[0]+1, nidx[0]+1, pis[1]+1, nidx[1]+1, pis[2]+1, nidx[2]+1))

    with open(obj_path, "w") as o:
        o.write(f"# {os.path.basename(stl_path)}: {ntri} tris, {len(verts)} verts, "
                f"{len(norms)} normals, crease={CREASE_ANGLE}deg\n")
        for x, y, z in verts:
            o.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
        for nx, ny, nz in norms:
            o.write(f"vn {nx:.4f} {ny:.4f} {nz:.4f}\n")
        for a, na, b, nb, c, nc in face_lines:
            o.write(f"f {a}//{na} {b}//{nb} {c}//{nc}\n")
    return ntri, len(verts), len(norms)


def main():
    src_dir, dst_dir = sys.argv[1], sys.argv[2]
    os.makedirs(dst_dir, exist_ok=True)
    total = 0
    for stl in sorted(glob.glob(os.path.join(src_dir, "*.stl"))):
        name = os.path.splitext(os.path.basename(stl))[0]
        if name == "base":          # stand kalibrasi, tak dipakai URDF
            continue
        obj = os.path.join(dst_dir, name + ".obj")
        ntri, nv, nn = convert(stl, obj)
        sz = os.path.getsize(obj); total += sz
        print(f"  {name:8s} {ntri:7d} tris -> {nv:7d} v / {nn:7d} vn  ({sz/1e6:.1f} MB)")
    print(f"Total OBJ: {total/1e6:.1f} MB")


if __name__ == "__main__":
    main()
