# IHASIMULASYON — TEKNOFEST 2026 Sabit Kanat İHA 3D Simülasyon Ortamı

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Bu depo, **TEKNOFEST 2026 TÜBİTAK Sabit Kanat İHA Yarışması (Şartname V6)** kapsamında geliştirilen otonom hedefleme, seyrüsefer ve balistik faydalı yük bırakma algoritmalarının **0 donanım riskiyle** test edildiği 3D fizik simülasyon ortamıdır.

---

## 📌 Özellikler

- **Gazebo Harmonic 3D Dünyası ([worlds/teknofest_2026.world](worlds/teknofest_2026.world)):**
  - $150 \times 15\text{ m}$ kalkış/iniş pisti ve $X=0$ başlangıç/bitiş çizgisi.
  - Aralarında net **150 metre** mesafe bulunan iki adet dönüş direği (Görev 1 yatay 8 / $\infty$ manevrası).
  - Şartnameye uygun hedef alanı:
    - **Hedef 1:** $4 \times 4\text{ m}$ Mavi Kare (Kırmızı yük hedefi).
    - **Hedef 2:** $2 \times 2\text{ m}$ Kırmızı Kare (Mavi yük hedefi).
    - **Negatif Test:** $2\text{ m}$ kenarlı Mavi Düzgün Altıgen ve $1\text{ m}$ kenarlı Kırmızı Eşkenar Üçgen (Döner kanat hedefleri — algoritma tespit etmemelidir).
- **TEKNOFEST Sabit Kanat Modeli ([models/teknofest_fixed_wing](models/teknofest_fixed_wing)):**
  - **Ağırlık:** $\text{MTOW} = 3.40\text{ kg} \le 4.0\text{ kg}$ şartname üst sınırı ($2.20\text{ kg}$ boş + $2\times 0.60\text{ kg}$ faydalı yük).
  - **Boyutlar:** $1.60\text{ m}$ kanat açıklığı, $1.15\text{ m}$ gövde uzunluğu (silindirik muhafaza kutusu uyumlu).
  - **Kontrol Yüzeyleri:** Bağımsız Eleron, Elevator, Burun Pervanesi (Gaz), Rudder ve Flaplar.
  - **Sensörler:** Gövde altında **30° öne açılı tek görev kamerası** (`1280x720` @ 30 FPS, Topic: `/camera/image_raw`) ve **1D AGL LiDAR** (`0.20 - 120.0 m`, Topic: `/rangefinder`).
  - **Yük Bırakma Mekanizması:** AUX 9 (Kırmızı Yük) ve AUX 10 (Mavi Yük) kanallarında `MAV_CMD_DO_SET_SERVO` (PWM 2000) tetikleme.

---

## 🚀 Hızlı Başlangıç

### 1. Gereksinimler & Kurulum (Ubuntu 22.04 LTS / WSL2)
```bash
chmod +x scripts/*.sh
./scripts/setup_ardupilot.sh
```

### 2. Başlatma (Windows için Hazır Kısayollar)
Klasör içindeki hazır `.bat` dosyalarına çift tıklayarak çalıştırabilirsiniz:
- `1_GAZEBO_BASLAT.bat` -> Gazebo Harmonic dünyasını ve İHA'yı açar.
- `2_SITL_BASLAT.bat` -> ArduPlane SITL otopilotunu başlatır.
- `3_OTONOMI_BASLAT.bat` -> IHAILOS otonomi yazılımını başlatır.

### Terminal Üzerinden Manuel Başlatma
```bash
# Terminal 1 — Gazebo
./scripts/run_gazebo.sh

# Terminal 2 — ArduPlane SITL
./scripts/run_sitl.sh

# Terminal 3 — Kamera Köprüsü (HTTP MJPEG)
./scripts/run_camera_bridge.sh
```

---

## 📖 Kılavuz & Belgeler
- **Detaylı Entegrasyon & CAD Tasarımı Ekleme:** [REHBER.md](REHBER.md)
- **Simülasyon Mimari Sözleşmesi:** [SIMULATION_BLUEPRINT.md](SIMULATION_BLUEPRINT.md)

---

## 📄 Lisans
Bu proje [MIT Lisansı](LICENSE) altında açık kaynak olarak lisanslanmıştır.
