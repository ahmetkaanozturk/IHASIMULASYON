# TEKNOFEST 2026 Sabit Kanat İHA - Simülasyon Blueprint (AI Context)

## 1. Amaç ve Kapsam

Bu çalışma alanı (`teknofest_sim_ws`), TEKNOFEST 2026 TÜBİTAK Sabit Kanat İHA Yarışması (Şartname V6) için geliştirilen otonom hedefleme, balistik yük bırakma ve seyrüsefer yazılımının (`IHAILOS`) 0 donanım riskiyle test edileceği 3D fizik simülasyon ortamıdır.

Ana otonomi yazılımı ayrı bir depodadır (`IHAILOS`); bu repo Gazebo dünyasını, TEKNOFEST şartnameli sabit kanat İHA modelini, ArduPilot SITL altyapısını ve sanal kamera yayınını barındırır.

## 2. Sistem ve Bağımlılık Yığını

- **İşletim Sistemi:** Ubuntu 22.04 LTS (x86_64)
- **Otopilot Simülasyonu:** ArduPilot (ArduPlane firmware) SITL
- **3D Fizik Motoru:** Gazebo Harmonic (`ardupilot_gazebo` plugin entegrasyonlu)
- **Haberleşme:** MAVLink (TCP: `127.0.0.1:5760` / UDP: `127.0.0.1:14550` [IHAILOS] & `127.0.0.1:14551` [QGC])
- **Kamera Köprüsü:** `scripts/run_camera_bridge.sh` ile HTTP MJPEG (`http://127.0.0.1:8554/stream.mjpg`) veya ROS 2 Humble (`/camera/image_raw`).

## 3. TEKNOFEST 2026 Şartname Kuralları ve Dünya Boyutları

Gazebo dünyası (`worlds/teknofest_2026.world`) şartnameye birebir uygun şu modelleri içerir:

1. **Pist ve Çizgi:** Başlangıç/Bitiş çizgisi ($X=0$) ve $150 \times 15\text{ m}$ kalkış pisti.
2. **Dönüş Direkleri:**
   - Direk 1 `(200, 75, 0)` ve Direk 2 `(200, -75, 0)` arası net mesafe: **150 metre**.
   - Görev 1 için sonsuz ($\infty$ - yatay 8) manevrası bu iki direğin etrafında dıştan dönülür.
3. **Sabit Kanat Hedefleri (Görüntü İşleme Alanı - Direk 2'nin ardındaki bölge):**
   - **Hedef 1:** $4 \times 4\text{ m}$ Mavi Kare Hedef (Kırmızı yük atılacak).
   - **Hedef 2:** $2 \times 2\text{ m}$ Kırmızı Kare Hedef (Mavi yük atılacak).
4. **Döner Kanat Hedefleri (Negatif Filtreleme Testi İçin):**
   - Her kenarı $2\text{ m}$ olan Mavi Düzgün Altıgen Hedef.
   - Her kenarı $1\text{ m}$ olan Kırmızı Eşkenar Üçgen Hedef.
   - *Kural:* Sabit kanat yapay zekası bu hedefleri kesinlikle algılamamalıdır.

## 4. Uçak Modeli ve Sanal Kamera (`models/teknofest_fixed_wing`)

- **Gövde (TEKNOFEST 2026 Sabit Kanat Şartnamesi V6 Uyumlu):** Geleneksel yüksek kanatlı sabit kanat (`teknofest_fixed_wing`), $1.60\text{ m}$ kanat açıklığı (silindirik muhafaza kutusuna uyumlu), 3 nokta tekerlekli iniş takımı, burun çekici pervane, bağımsız eleron (`SERVO1`) + irtifa dümeni (`SERVO2`) + gaz (`SERVO3`) + yön dümeni (`SERVO4`) + flap (`SERVO5`) kontrol yüzeyleri.
- **Ağırlık (Madde 3.1):** Yüksüz $W_0 = 2.20\text{ kg}$ + 2 adet pasif faydalı yük ($0.60\text{ kg}$ Kırmızı Yük + $0.60\text{ kg}$ Mavi Yük) = **Toplam Kalkış Ağırlığı (MTOW) $3.40\text{ kg} \le 4.0\text{ kg}$**.
- **Sensör (Madde 4.2):** Gövde altına monte edilmiş tek görev kamerası; uçuş yönüne doğru **30° öne açılı (pitch down)** çalışan sanal RGB kamera (`1280x720`, 30 FPS, `HFOV = 1.014197 rad` / `fx = 1152.0`, Topic: `/camera/image_raw`).
- **LiDAR / Rangefinder (Madde 3.5 & 10):** Gövde altında AGL irtifasını ölçen sanal 1D mesafe sensörü (`0.20 m - 120.0 m`, Topic: `/rangefinder`, MAVLink `DISTANCE_SENSOR`).
- **Aktüatör:** AUX 9 (`SERVO9_FUNCTION=0`, Kırmızı Yük) ve AUX 10 (`SERVO10_FUNCTION=0`, Mavi Yük) kanallarında `MAV_CMD_DO_SET_SERVO` (PWM 2000) uyumlu sanal faydalı yük bırakma pimleri.

## 5. Çalıştırma Sırası

1. **Kurulum (tek seferlik):** `./scripts/setup_ardupilot.sh`
2. **Terminal 1 (Gazebo):** `./scripts/run_gazebo.sh`
3. **Terminal 2 (ArduPlane SITL):** `./scripts/run_sitl.sh`
4. **Terminal 3 (Kamera Köprüsü):** `./scripts/run_camera_bridge.sh`
5. **Terminal 4 (IHAILOS Ana Yazılım):**
   ```bash
   python main.py --mavlink udp:127.0.0.1:14550 --camera http://127.0.0.1:8554/stream.mjpg --model yolov8n.pt
   ```
