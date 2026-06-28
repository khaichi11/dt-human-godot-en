# OP3 Digital Twin — Alur Operasi & Action Editor

> Spec alur aplikasi, dipetakan PERSIS ke siklus *action editor* ROBOTIS OP3 dan
> topik ROS2 aslinya. Jadi acuan sebelum membangun (Fase 4).

## State machine

```
[1] MODEL READY (offline)
     │  Connect  (rosbridge WebSocket ws://robot:9090)
     ▼
[2] CONNECTED · MONITORING
     │   ← langganan telemetri: pose, status, IMU, baterai, kesehatan servo
     │   robot di DT meniru pose NYATA saat ini (present_joint_states)
     │
     │  Activate  (urutan resmi op3_manager)
     │   ├─ torque ON semua Dynamixel   → /robotis/sync_write_item (torque_enable=1)
     │   ├─ ke pose awal                → /robotis/base/ini_pose  ("ini_pose")
     │   └─ pilih control module        → /robotis/enable_ctrl_module
     ▼
[3] ACTIVATED · READY POSE
     │   robot tegak di pose ready (walk-ready / ini_pose). Baru boleh diatur.
     │
     │  Buka Action Editor
     ▼
[4] EDITING  (Action Editor — semua menu di sini)
     ├─ Page (motion)  →  Step/SCENE (maks 7)  →  params
     └─ 3 mode atur pose  (lihat di bawah)
```

Mapping ke 7 poin yang diminta:

| Poin | Maksud | Status / mekanik |
|---|---|---|
| 1 | Robot (model) ada | ✓ ada (OP3Robot 20-DOF) |
| 2 | Konekin robot | ✓ ada (RosBridge ws) |
| 3 | Setelah konek → pose default idle + semua info muncul | pose dari `present_joint_states`; baterai/servo/IMU dari topik (lihat tabel) |
| 4 | "Aktifkan robot" lewat action editor | urutan torque-on → ini_pose → enable_ctrl_module |
| 5 | Setelah aktif → pose ready → baru diatur | state [3] → [4] |
| 6 | Tambah scene, 3 opsi atur pose | Step = "scene"; 3 mode (a/b/c) |
| 7 | Load beda → atur turun-kaki, bungkuk, dll | param walking/tuning per-action |

---

## "Scene" = Step dalam Page  (dari action_file_define.h)

- 1 **Page** = satu gerakan/motion. Maks **256 page**, tiap page maks **7 Step**.
- 1 **Step** (= "scene" yang kamu maksud) = posisi semua joint + `pause` + `time`
  (durasi gerak ke step itu).
- Header page: `name`, `repeat`, `speed`, `accel`, `next`, `exit`, `pgain` per-joint.
- Flag penting: **`TORQUE_OFF_BIT_MASK 0x2000`** per-joint → dipakai opsi (b).

DT menyimpan page/step sebagai data sendiri (JSON), dan bisa **ekspor/impor**
ke format `.bin` ROBOTIS bila perlu kompatibel dengan robot.

---

## 3 Mode Atur Pose (poin 6)

### (a) Virtual-first — atur di DT dulu
Susun pose di DT (slider/gizmo), simpan sebagai Step. **Tiap scene punya tombol
"Coba di robot asli"** → publish pose itu ke robot sesaat untuk verifikasi sesuai
jalannya. Aman: robot hanya bergerak saat tombol ditekan.

### (b) Hand-pose — lemaskan servo lalu kaku  *(seperti action editor asli)*
Pilih servo tertentu → **torque OFF** servo itu (`sync_write_item`,
torque_enable=0 utk ID terpilih) → gerakkan tangan secara fisik → **Capture**
(baca `present_joint_states` → simpan ke Step) → **torque ON** lagi.
Ini cara ROBOTIS asli "mengajari" pose.

### (c) Live-sync — DT & robot bergerak bareng
Saat menggeser di DT, stream perintah ke robot real-time (`set_joint_states`).
Robot ikut bergerak seketika. **Butuh guard** (centang "live", limit kecepatan,
E-stop) karena robot bergerak terus.

> Default aman = **(a)**. Mode (b) & (c) menggerakkan robot fisik → wajib
> konfirmasi + E-stop + robot tertopang.

---

## Parameter per-action (poin 7 — load tak selalu sama)

Karena beban/permukaan berbeda, action editor menyediakan tuning (nilai default
dari `op3_walking_module/config/param.yaml`):

| Parameter | Arti (istilahmu) | Default |
|---|---|---|
| `hip_pitch_offset` | seberapa **bungkuk** badan | 7° |
| `foot_height` | tinggi angkat / **turun kaki** | 0.06 m |
| `z_offset` | tinggi pinggul | 0.035 m |
| `x_offset` / `y_offset` | geser CoM maju/samping | -0.02 / 0.015 |
| `period_time` | kecepatan langkah | 600 ms |
| `arm_swing_gain` | ayun lengan | 0.2 |
| `balance_*_gain` | gain keseimbangan (knee/ankle/hip) | 0.3–0.9 |

Plus **offset per-servo** dari `op3_tuning_module/data/offset.yaml` (kalibrasi
mekanik tiap sendi).

---

## Topik / service ROS2 yang dipakai (terverifikasi dari sumber)

| Fungsi | Topik / service | Tipe |
|---|---|---|
| Pose nyata (monitor) | `/robotis/present_joint_states` | `sensor_msgs/JointState` |
| Kirim perintah pose | `/robotis/set_joint_states` | `sensor_msgs/JointState` |
| IMU badan | `/robotis/open_cr/imu` | `sensor_msgs/Imu` |
| Torque on/off + power | `/robotis/sync_write_item` | `…/SyncWriteItem` |
| Ke pose awal | `/robotis/base/ini_pose` | `std_msgs/String` |
| Pilih control module | `/robotis/enable_ctrl_module` | `std_msgs/String` |
| Set module per-joint | `/robotis/set_present_ctrl_modules` | srv `…/SetModule` |
| Status/feedback robot | `/robotis/status` | `…/StatusMsg` |
| Putar action page | `/robotis/action/page_num` *(verifikasi)* | `std_msgs/Int32` |

Control module yang relevan: `action_module` (putar page), `none`/
`direct_control_module` (atur joint langsung dari DT), `walking_module` (jalan).

---

## Rencana bangun (incremental)

1. **Activation panel** — tombol Activate (torque-on → ini_pose → enable module) +
   baca `/robotis/status` untuk konfirmasi state [2]→[3].
2. **Action Editor inti** — daftar Page → Step/scene (tambah/hapus/urut), simpan
   pose tiap step, `pause`/`time`, putar preview di DT.
3. **3 mode atur pose** (a → b → c), dengan guard keamanan.
4. **Panel tuning** — slider param tabel di atas, per-action.
5. **Ekspor/impor** `.bin` ROBOTIS (opsional, kompatibilitas).
