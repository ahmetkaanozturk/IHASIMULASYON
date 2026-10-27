# TEKNOFEST 2026 Sabit Kanat İHA — Simülasyon ve Otonomi Kılavuzu

Bu belge, **TEKNOFEST 2026 Sabit Kanat İHA Yarışması (Şartname V6)** kapsamında geliştirilen **3D Fizik Simülasyonu (`IHASIMULASYON`)** ile **Otonom Hedefleme ve Görev Kontrol Yazılımının (`IHAILOS`)** mimarisini, çalışma prensiplerini ve takıma özel İHA tasarımlarının ortama nasıl ekleneceğini açıklar.

---

## 1. Mimari Genel Bakış

Sistem üç ana katmandan oluşur ve donanım riski olmadan tam kapalı çevrim (Closed-Loop SITL) test imkânı sunar:

```
┌─────────────────────────────────────────────────────────────┐
│                 GAZEBO HARMONIC (Fizik & Dünya)            │
│  - 150 m Pist & Başlangıç Çizgisi                           │
│  - 150 m Aralıklı 2 Dönüş Direği (∞ Manevrası)              │
│  - 4x4m Mavi & 2x2m Kırmızı Hedefler                        │
│  - Negatif Test Hedefleri (2m Altıgen, 1m Üçgen)            │
│  - TEKNOFEST Sabit Kanat Modeli (LiftDrag Aerodinamik)      │
│  - 30° Öne Açılı Görev Kamerası + AGL LiDAR Sensörü        │
└──────────────────────────────┬──────────────────────────────┘
                               │ JSON Köprüsü (Port 9002)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  ARDUPILOT (ArduPlane SITL)                 │
│  - Uçuş Kontrolcüsü & Durum Kestirimi (EKF3)                │
│  - Konum: Ankara (39.925533, 32.866287, 890m, HDG 90°)     │
│  - Kontrol Yüzeyleri: Eleron, Elevator, Gaz, Rudder, Flap   │
│  - Yük Bırakma: AUX 9 (Kırmızı Yük) & AUX 10 (Mavi Yük)     │
└──────────────────────────────┬──────────────────────────────┘
                               │ MAVLink (UDP: 14550) + Kamera (MJPEG)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     IHAILOS (Otonomi Motoru)                │
│  - 5 İş Parçacıklı Mimari:                                  │
│    1) Telemetri (10 Hz) -> Zaman senkronizasyonu             │
│    2) Görüntü (5 Hz)    -> YOLO + 8-Kare Doğrulama           │
│    3) Kestirim (10 Hz)  -> Pinhole + WGS84 Geo-Ref + Kalman │
│    4) Görev (10 Hz)     -> FSM + Geofence + Emniyet         │
│    5) İletişim (5 Hz)   -> Hakem Telemetrisi & Fotoğraf     │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Şartnameye Uygunluk Özeti

| Kriter | TEKNOFEST Şartnamesi (V6) | Simülasyon Karşılığı |
|--------|---------------------------|----------------------|
| **Kategori** | Sabit Kanat (VTOL/DİKY yasak) | Geleneksel yüksek kanatlı sabit kanat modeli |
| **Toplam Ağırlık** | MTOW $\le 4.0\text{ kg}$ | $3.40\text{ kg}$ ($2.20\text{ kg}$ boş + $2\times 0.60\text{ kg}$ yük) |
| **Muhafaza Kutusu** | Silindirik kutuya sığabilir | $1.60\text{ m}$ demonte kanat açıklığı, $1.15\text{ m}$ gövde |
| **Direk Aralığı** | Net $150\text{ m}$ | `pole_1` $(200, 75)$ ile `pole_2` $(200, -75)$ arası $150\text{ m}$ |
| **Hedefler (G2)** | $4\times 4\text{ m}$ Mavi (Kırmızı yük) & $2\times 2\text{ m}$ Kırmızı (Mavi yük) | Birebir boyut ve albedoda Gazebo SDF modelleri |
| **Negatif Hedefler** | $2\text{ m}$ Altıgen & $1\text{ m}$ Üçgen (tespit edilmemeli) | Doğrulanmış STL geometrileri tarama alanında aktif |
| **Kamera Açısı** | Tek kamera, gövde altı | $30^\circ$ pitch-down açılı sanal kamera (`1280x720` @ 30 FPS) |
| **İrtifa Limiti** | SHGM AGL $\le 120\text{ m}$ | 1D LiDAR (`0.20 - 120.0 m`), limit dışı olursa otonomi kilitlenir |

---

## 3. Kurulum ve Çalıştırma

### 3.1 Gereksinimler
- **İşletim Sistemi:** Windows 10/11 (WSL2 - Ubuntu 22.04 LTS) veya yerel Ubuntu 22.04
- **Yazılımlar:** Gazebo Harmonic, ArduPilot SITL, Python 3.10+

### 3.2 Tek Seferlik Kurulum
Ubuntu (WSL) terminalinde proje dizinine gidip:
```bash
chmod +x scripts/*.sh
./scripts/setup_ardupilot.sh
```

### 3.3 Sistemi Başlatma
`IHASIMULASYON` klasöründeki hazır başlatıcıları çift tıklayarak çalıştırabilirsiniz:
1. **`1_GAZEBO_BASLAT.bat`**: Gazebo Harmonic 3D dünyasını ve İHA'yı açar.
2. **`2_SITL_BASLAT.bat`**: ArduPlane otopilotunu ve MAVProxy haritasını başlatır.
3. **`3_OTONOMI_BASLAT.bat`**: IHAILOS otonomi yazılımını başlatır.

Alternatif olarak terminal üzerinden:
```bash
# Terminal 1
./scripts/run_gazebo.sh

# Terminal 2
./scripts/run_sitl.sh

# Terminal 3
./scripts/run_camera_bridge.sh

# Terminal 4 (IHAILOS dizininde)
python main.py --mavlink udp:127.0.0.1:14550 --camera http://127.0.0.1:8554/stream.mjpg --model yolov8n.pt
```

---

## 4. Kendi Tasarımınızı Simülasyona Ekleme Rehberi

Takımınızın SolidWorks / CATIA / Fusion 360'ta modellediği özgün sabit kanat İHA'yı ortama aktarmak için:

### Adım 1: 3D Parçaları STL Olarak Dışa Aktarın
CAD programınızda uçağı orijini **ağırlık merkezi (CG)** olacak şekilde parçalara ayırıp STL olarak dışa aktarın:
- `models/kendi_ihaniz/meshes/fuselage.stl` (Gövde + İniş Takımı)
- `models/kendi_ihaniz/meshes/propeller.stl` (Pervane)
- `models/kendi_ihaniz/meshes/aileron_left.stl`, `aileron_right.stl` (Eleronlar)
- `models/kendi_ihaniz/meshes/elevator.stl` (İrtifa Dümeni)
- `models/kendi_ihaniz/meshes/rudder.stl` (Yön Dümeni)
- `models/kendi_ihaniz/meshes/flap_left.stl`, `flap_right.stl` (Flaplar)

### Adım 2: Kütle ve Atalet Matrisini Girin
CAD programınızın "Kütle Özellikleri" (Mass Properties) penceresinden aldığınız değerleri `model.sdf` dosyasındaki `<inertial>` etiketine yazın:
```xml
<inertial>
  <pose>0 0 0 0 0 0</pose>
  <mass>3.20</mass> <!-- Toplam kg -->
  <inertia>
    <ixx>0.185</ixx>
    <iyy>0.240</iyy>
    <izz>0.380</izz>
    <ixy>0</ixy><ixz>0.01</ixz><iyz>0</iyz>
  </inertia>
</inertial>
```

### Adım 3: Kanat Profili Aerodinamiğini Tanımlayın
Kanadınızın profil özelliklerini (`LiftDrag` sistemi) ekleyin:
- `cla`: Taşıma katsayısı eğimi ($\approx 2\pi \approx 5.0 - 6.0$)
- `cda`: Sürükleme katsayısı ($\approx 0.04 - 0.08$)
- `alpha_stall`: Perdövites (stall) açısı ($\approx 0.25 - 0.35\text{ rad}$)
- `area`: Kanat yüzey alanı ($m^2$)

### Adım 4: ArduPilot Eşlemesi
`model.sdf` içindeki `ArduPilotPlugin` bloğunda:
- `channel 0` -> Sol/Sağ Eleron
- `channel 1` -> Elevator
- `channel 2` -> Gaz (Propeller)
- `channel 3` -> Rudder
- `channel 4` -> Flaplar
şeklinde eklem kontrollerini bağlayın.

---

## 5. Dizin Yapısı

```
IHASIMULASYON/
├── SIMULATION_BLUEPRINT.md    <- Simülasyon mimari sözleşmesi
├── REHBER.md                  <- Bu dokümantasyon
├── 1_GAZEBO_BASLAT.bat        <- Tek tıkla Gazebo başlatıcı
├── 2_SITL_BASLAT.bat          <- Tek tıkla ArduPlane SITL başlatıcı
├── 3_OTONOMI_BASLAT.bat       <- Tek tıkla Otonomi başlatıcı
├── models/
│   ├── teknofest_fixed_wing/  <- TEKNOFEST şartnameli sabit kanat İHA
│   ├── pole/                  <- Dönüş direkleri
│   ├── target_blue_square_4x4/<- 4x4m mavi hedef
│   ├── target_red_square_2x2/ <- 2x2m kırmızı hedef
│   ├── target_blue_hexagon/   <- Döner kanat negatif hedefi (2m)
│   └── target_red_triangle/   <- Döner kanat negatif hedefi (1m)
├── scripts/
│   ├── setup_ardupilot.sh     <- ArduPilot & Gazebo kurulum betiği
│   ├── run_gazebo.sh          <- Gazebo başlatıcı
│   ├── run_sitl.sh            <- ArduPlane SITL başlatıcı
│   ├── run_camera_bridge.sh   <- MJPEG & ROS 2 kamera köprüsü
│   └── sitl_params/           <- Şartname uyumlu ArduPlane parametreleri
└── worlds/
    └── teknofest_2026.world   <- Koordinatlı resmi yarışma dünyası
```

