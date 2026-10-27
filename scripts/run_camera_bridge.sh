#!/usr/bin/env bash
# =============================================================================
# TEKNOFEST 2026 — Gazebo /camera/image_raw → OpenCV MJPEG & ROS 2 Kamera Köprüsü
# =============================================================================
# İki çalışma modu destekler:
#   1) Varsayılan (--mjpeg): Gazebo /camera/image_raw topiğinden kareleri alır ve
#      http://127.0.0.1:8554/stream.mjpg adresinden MJPEG olarak yayınlar.
#      IHAILOS ile kullanım:
#        python main.py --mavlink udp:127.0.0.1:14550 \
#                       --camera http://127.0.0.1:8554/stream.mjpg \
#                       --model yolov8n.pt
#   2) ROS 2 (--ros2): ros_gz_image ile /camera/image_raw ROS 2 topiğine köprüler.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env

MODE="mjpeg"
PORT="${TEKNOFEST_CAM_PORT:-8554}"
GZ_TOPIC="${TEKNOFEST_GZ_CAM_TOPIC:-/camera/image_raw}"

usage() {
  cat <<EOF
Kullanım: $0 [--mjpeg] [--ros2] [--port PORT] [--topic TOPIC]

  --mjpeg        HTTP MJPEG akışı (varsayılan → http://127.0.0.1:${PORT}/stream.mjpg)
  --ros2         ROS 2 Humble ros_gz_image köprüsü (/camera/image_raw)
  --port PORT    MJPEG HTTP portu (varsayılan: 8554)
  --topic TOPIC  Gazebo kamera topiği (varsayılan: /camera/image_raw)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mjpeg) MODE="mjpeg"; shift ;;
    --ros2) MODE="ros2"; shift ;;
    --port) PORT="${2:?}"; shift 2 ;;
    --topic) GZ_TOPIC="${2:?}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Bilinmeyen argüman: $1" ;;
  esac
done

if [[ "${MODE}" == "ros2" ]]; then
  require_cmd ros2
  log "ROS 2 kamera köprüsü başlatılıyor: ${GZ_TOPIC}"
  exec ros2 run ros_gz_image image_bridge "${GZ_TOPIC}"
fi

require_cmd python3
log "Gazebo → OpenCV MJPEG kamera köprüsü başlatılıyor..."
log "  Gazebo Topic : ${GZ_TOPIC}"
log "  IHAILOS URL  : http://127.0.0.1:${PORT}/stream.mjpg"

exec python3 - "${GZ_TOPIC}" "${PORT}" <<'PYEOF'
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
import numpy as np

TOPIC = sys.argv[1]
PORT = int(sys.argv[2])

latest_jpeg = None
frame_lock = threading.Lock()
frame_event = threading.Event()


def make_placeholder_jpeg() -> bytes:
    img = np.zeros((720, 1280, 3), dtype=np.uint8)
    img[:] = (40, 45, 40)
    cv2.putText(
        img,
        f"Waiting for Gazebo topic: {TOPIC}",
        (60, 360),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.0,
        (0, 220, 255),
        2,
        cv2.LINE_AA,
    )
    ok, buf = cv2.imencode(".jpg", img, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
    return buf.tobytes() if ok else b""


latest_jpeg = make_placeholder_jpeg()


def on_gz_image(msg) -> None:
    global latest_jpeg
    try:
        w = int(msg.width)
        h = int(msg.height)
        if w <= 0 or h <= 0:
            return
        arr = np.frombuffer(msg.data, dtype=np.uint8)
        if arr.size < w * h * 3:
            return
        rgb = arr[: w * h * 3].reshape((h, w, 3))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        ok, buf = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
        if ok:
            with frame_lock:
                latest_jpeg = buf.tobytes()
            frame_event.set()
    except Exception as exc:
        sys.stderr.write(f"[WARN] Kare dönüştürme hatası: {exc}\n")


def start_gz_subscriber() -> None:
    try:
        from gz.msgs10.image_pb2 import Image
        from gz.transport13 import Node
    except ImportError:
        sys.stderr.write(
            "[WARN] python3-gz-transport13 / python3-gz-msgs10 bulunamadı; "
            "yedek test akışı yayınlanıyor.\n"
        )
        return

    node = Node()
    if not node.subscribe(Image, TOPIC, on_gz_image):
        sys.stderr.write(f"[ERR ] Gazebo topiğine abone olunamadı: {TOPIC}\n")
        return
    print(f"[INFO] Gazebo topiği dinleniyor: {TOPIC}", flush=True)
    while True:
        time.sleep(1.0)


class MjpegHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path not in ("/", "/stream.mjpg", "/video"):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Age", "0")
        self.send_header("Cache-Control", "no-cache, private")
        self.send_header("Pragma", "no-cache")
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
        self.end_headers()
        try:
            while True:
                frame_event.wait(timeout=0.1)
                frame_event.clear()
                with frame_lock:
                    jpg = latest_jpeg
                if not jpg:
                    continue
                self.wfile.write(b"--frame\r\n")
                self.wfile.write(b"Content-Type: image/jpeg\r\n")
                self.wfile.write(f"Content-Length: {len(jpg)}\r\n\r\n".encode("ascii"))
                self.wfile.write(jpg)
                self.wfile.write(b"\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt: str, *args) -> None:
        return


if __name__ == "__main__":
    t = threading.Thread(target=start_gz_subscriber, daemon=True)
    t.start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), MjpegHandler)
    print(f"[INFO] MJPEG sunucu hazır: http://127.0.0.1:{PORT}/stream.mjpg", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
PYEOF

