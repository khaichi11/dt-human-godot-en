# OP3 Digital Twin — Di Mana Pembedanya?

> Dokumen posisi: kenapa proyek ini **bukan "simulator lagi"**, dan di titik
> mana ia berbeda dari Webots, Gazebo, RViz, Isaac Sim, RoboDK, dll.

## TL;DR

Kalau aplikasi ini cuma menampilkan model 3D OP3 yang bisa diorbit, itu sebuah
**viewer** — dan RViz/Webots sudah lebih lengkap. Pembedanya **bukan di grafis**.

Pembedanya: ini **cermin live dua arah dari OP3 _fisik_**, difokuskan untuk
**operasi + diagnostik real-time** unit nyata di lapangan.

> Catatan jujur: simulator modern (Gazebo, Isaac Sim, Webots) **juga bisa** disetel
> jadi digital twin. Jadi pembeda sebenarnya **bukan** kategori "twin vs sim" — tapi
> *engine vs produk*, *beban deployment*, dan *analitik di atasnya*. Lihat bagian di bawah.

```
                 DUNIA MAYA (robot fiktif)        ROBOT FISIK (unit nyata)
  PRE-DEPLOY     Webots, Gazebo, Isaac Sim   │
  (uji/dev)      RoboDK, Choreonoid          │
  ───────────────────────────────────────────┼─────────────────────────────────
  OPERASI        (—)                          │   ★ OP3 DIGITAL TWIN
  (pantau/rawat)                              │   konsol operasi & diagnostik
```

Simulator menjawab *"apakah controller-ku akan jalan?"*.
Digital twin menjawab *"apa yang sedang dilakukan & dialami robotku **sekarang**,
dan apakah ia menyimpang dari yang seharusnya?"*.

---

## Twin vs Simulator — beda mendasar

| Aspek | Simulator (Webots/Gazebo/Isaac) | **OP3 Digital Twin (ini)** |
|---|---|---|
| Sumber kebenaran | Model fisika dunia fiktif | **Telemetri OP3 fisik (live)** |
| Arah data | Open-loop ke robot nyata | **Bidirectional**: telemetri masuk, perintah/prediksi keluar |
| Kapan dipakai | Sebelum deploy (uji controller, sim-to-real) | **Saat robot beroperasi** (monitor, diagnosa, rawat) |
| Pertanyaan yang dijawab | "Akankah jalan?" | "Sedang apa? Sehat? Menyimpang?" |
| Servo rusak/panas | Tidak pernah (fiktif) | **Nyata** — bisa di-trend & diprediksi |
| Nilai utama | Pengembangan | **Uptime, keselamatan, perawatan** |

> Bukan saingan Webots — **komplementer**. Webots untuk membangun controller;
> twin ini untuk **menjalankan & menjaga** OP3 setelah controller itu di robot.

---

## "Tapi Gazebo/Isaac juga bisa jadi twin" — betul. Lalu di mana bedanya?

Koreksi penting: kategori "simulator vs twin" itu **terlalu rapi**. Gazebo
(`gz-sim` + `ros2_control`), NVIDIA Isaac Sim/Omniverse, dan Webots **bisa** disetel
jadi platform digital twin — menyerap topik ROS2 live, mencerminkan robot nyata,
bahkan forward-sim prediktif. Isaac bahkan memasarkan "digital twin" terang-terangan.

Jadi pembedanya **bukan kemampuan kategori**, tapi tiga hal:

1. **Engine vs Produk.** Gazebo/Isaac itu *engine* fisika+render serba-guna; "twin"
   adalah kapabilitas yang kamu **rakit sendiri** (URDF, plugin, panel RViz, rqt,
   dashboard custom). Ini = **produk operasi & diagnostik OP3 yang sudah jadi &
   beropini**. Pembeda = spesialisasi + UX, bukan kapabilitas mentah.

2. **Beban & deployment.** Engine sim itu **berat** (Isaac butuh GPU RTX; Gazebo
   butuh stack sim penuh). Memantau robot nyata **tidak butuh physics engine jalan**
   — butuh visualisasi + diagnosa state nyata. Dashboard Godot ringan: jalan di NUC
   / laptop / tablet operator di lapangan, tanpa overhead simulasi.

3. **Yang dihitung di atasnya (moat sebenarnya).** "Mirror 3D yang sinkron" itu
   **komoditas** (RViz/Gazebo bisa). Nilai aslinya = lapisan analitik khas operasi
   OP3 + **integrasi robot + NUC + vision (YOLO) jadi SATU narasi operator**. Gazebo
   tidak menggabungkan CPU NUC + YOLO head-cam + termal servo jadi satu cerita
   diagnosa — kamu tetap harus bangun sendiri. *Itulah* produknya.

> Kicker jujur: kamu bahkan bisa pakai Gazebo/Isaac sebagai **sumber data atau
> backend prediktif**, dan tetap differentiate di lapisan **aplikasi + UX +
> diagnostik**. Konsekuensinya: proyek ini harus **bersandar kuat ke analitik +
> integrasi + UX**, karena mirror 3D semata bukan pembeda.

---

## 4 Kapabilitas Inti yang Diintegrasikan

Bukan klaim "simulator tak bisa", tapi inilah kapabilitas yang produk ini
**integrasikan & poles** jadi pengalaman operator OP3 — dan repo ini sudah ke sana:

### 1. Live Hardware Mirror
Pose, beban, suhu tiap servo; IMU/FT; baterai; beban NUC; head-cam + deteksi bola
YOLO — semuanya **ground-truth unit nyata**, bukan angka simulasi.
- Sudah ada: `RosBridge.gd`, `SensorPanel.gd`, monitor NUC (btop), panel CV.

### 2. Divergence: Commanded vs Measured  ★ tanda tangan digital twin
Overlay **pose perintah (ghost)** vs **pose terukur**. Selisihnya (residu) =
sinyal anomali: backlash, tabrakan, slip, servo lemah/mati.
- Simulator tak punya ini — tidak ada robot nyata yang bisa "menyimpang".
- Status: **belum ada** → kandidat fitur headline.

### 3. Health & Predictive Maintenance
Tren suhu/beban servo, duty-cycle, prediksi fault sebelum gagal.
- Sudah ada benih: deteksi servo fault-red di 17/20 link → tinggal di-*trend*-kan
  jadi grafik + ambang alarm + estimasi sisa umur.

### 4. Supervisory Ops HMI
Konsol untuk **mengoperasikan & mengawasi** robot nyata dengan aman: state, mode
AUTO/MANUAL, E-stop, alarm, event log, rekam & playback sesi.
- Webots itu sandbox dev, bukan konsol operasi. Status: **belum ada**.

---

## Apa Ini / Apa Ini Bukan

**Ini:**
- Konsol operasi & diagnostik untuk OP3 **fisik**.
- Lapisan kecerdasan di atas telemetri: deteksi divergensi, kesehatan, alarm.
- Jendela tunggal: robot + NUC + persepsi (vision) dalam satu pandangan.

**Ini bukan:**
- Simulator fisika / lingkungan uji controller (itu ranah Webots/Gazebo).
- Sekadar viewer 3D (itu sudah dilakukan RViz).
- Pengganti Dynamixel Wizard (itu tool servo low-level; twin meng-*agregat*-nya).

---

## Peta Fitur Pembeda (status & arah)

| Fitur pembeda | Status | Catatan |
|---|---|---|
| Live mirror joint/IMU/FT/batt | ◐ sebagian | via RosBridge + SensorPanel |
| Monitor NUC (CPU/mem/net) | ✓ ada | gaya btop |
| Vision live (head-cam + YOLO) | ✓ ada | panel CV |
| Servo fault highlight | ✓ ada | 17/20 link |
| **Divergence overlay (ghost vs real)** | ✗ belum | ★ kandidat headline |
| **Trend suhu/beban + alarm** | ✗ belum | dari fault-red → time-series |
| **Event log + playback sesi** | ✗ belum | rekam-putar operasi nyata |
| **Mode/E-stop supervisory** | ✗ belum | keselamatan operasi |

---

## Referensi posisi
- "Digital twin" (Grieves/NASA): pasangan virtual yang **tersinkron** dengan aset
  fisik sepanjang siklus hidupnya — penekanan pada *sinkronisasi live*, bukan
  sekadar model.
- Webots / Gazebo / Isaac Sim: simulator robotika (pre-deployment).
- RViz: visualisasi state ROS (viewer), bukan konsol operasi/diagnostik.

> Catatan: dokumen ini soal **posisi/diferensiasi**, bukan gaya visual. Arah
> visual (game/FUI HUD) dibahas terpisah di design-system.
