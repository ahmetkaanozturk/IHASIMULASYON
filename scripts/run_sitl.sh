#!/usr/bin/env bash
# =============================================================================
# TEKNOFEST 2026 — ArduPlane SITL başlatıcı (Gazebo JSON köprüsü)
# Önkoşul: ./scripts/setup_ardupilot.sh  ve  ./scripts/run_gazebo.sh (önce Gazebo)
# Kullanım: ./scripts/run_sitl.sh [--no-mavproxy] [--instance N]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env

INSTANCE=0
START_MAVPROXY=1
EXTRA_ARGS=()

usage() {
  cat <<EOF
Kullanım: $0 [seçenekler]

  --no-mavproxy   Yerleşik MAVProxy konsol/harita açma
  --instance N    SITL örneği (varsayılan 0 → TCP 5760, UDP 14550 & 14551)
  --help          Bu yardım

Ortam (env.sh):
  TEKNOFEST_SITL_VEHICLE   varsayılan ArduPlane
  TEKNOFEST_SITL_FRAME     varsayılan plane (geleneksel sabit kanat)
  TEKNOFEST_SITL_LOCATION  varsayılan 39.925533,32.866287,890,90 (Ankara pist orijini, Doğu yönü)
  TEKNOFEST_SITL_JSON_PORT varsayılan 9002
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-mavproxy) START_MAVPROXY=0; shift ;;
    --instance) INSTANCE="${2:?}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

[[ -d "${ARDUPILOT_HOME}" ]] || die "ARDUPILOT_HOME yok: ${ARDUPILOT_HOME}. Önce setup_ardupilot.sh çalıştırın."
[[ -x "${ARDUPILOT_HOME}/build/sitl/bin/arduplane" ]] \
  || die "arduplane derlenmemiş. ./scripts/setup_ardupilot.sh çalıştırın."

export PATH="${HOME}/.local/bin:${ARDUPILOT_HOME}/Tools/autotest:${PATH}"
require_cmd python3

VEHICLE="${TEKNOFEST_SITL_VEHICLE:-ArduPlane}"
FRAME="${TEKNOFEST_SITL_FRAME:-plane}"
JSON_PORT="${TEKNOFEST_SITL_JSON_PORT:-9002}"
# worlds/teknofest_2026.world küresel koordinatları + pist doğrultusu (ENU +X = 90° Doğu)
CUSTOM_LOCATION="${TEKNOFEST_SITL_LOCATION:-39.925533,32.866287,890,90}"

# Instance ofsetleri (ArduPilot standardı)
TCP_BASE=$((5760 + INSTANCE * 10))
UDP_BASE=$((14550 + INSTANCE * 10))
UDP_GCS=$((UDP_BASE + 1))

PARAM_DIR="${WS_ROOT}/scripts/sitl_params"
mkdir -p "${PARAM_DIR}"
PARAM_FILE="${PARAM_DIR}/teknofest_plane.parm"

# TEKNOFEST 2026 Sabit Kanat Şartnamesi (V6) + IHAILOS uyumlu SITL parametreleri
if [[ "${TEKNOFEST_KEEP_PARM:-0}" -ne 1 ]] || [[ ! -f "${PARAM_FILE}" ]]; then
  cat > "${PARAM_FILE}" <<'EOF'
# =============================================================================
# TEKNOFEST 2026 Sabit Kanat İHA — ArduPlane SITL Parametreleri (Şartname V6)
# =============================================================================
# Geleneksel Sabit Kanat Kontrol Yüzeyleri (models/teknofest_fixed_wing uyumlu)
SERVO1_FUNCTION 4
SERVO2_FUNCTION 19
SERVO3_FUNCTION 70
SERVO4_FUNCTION 21
SERVO5_FUNCTION 84

# Görev 2 Faydalı Yük Bırakma Kanalları (AUX 9: Kırmızı Yük, AUX 10: Mavi Yük)
# IHAILOS MAV_CMD_DO_SET_SERVO (PWM 2000) komutunun çalışması için FUNCTION=0 olmalıdır
SERVO9_FUNCTION 0
SERVO9_MIN 1000
SERVO9_MAX 2000
SERVO9_TRIM 1000
SERVO10_FUNCTION 0
SERVO10_MIN 1000
SERVO10_MAX 2000
SERVO10_TRIM 1000

# Aşağı Yönlü AGL Rangefinder (SHGM <= 120 m kuralı & IHAILOS DISTANCE_SENSOR kapısı)
RNGFND1_TYPE 100
RNGFND1_ORIENT 25
RNGFND1_MIN_CM 20
RNGFND1_MAX_CM 12000

# MAVLink Telemetri Akış Hızları (DISTANCE_SENSOR, GLOBAL_POSITION_INT, ATTITUDE)
SR0_EXTRA1 10
SR0_EXTRA2 10
SR0_EXTRA3 10
SR0_POSITION 10
SR0_EXT_STAT 5
SR1_EXTRA1 10
SR1_EXTRA2 10
SR1_EXTRA3 10
SR1_POSITION 10
SR1_EXT_STAT 5
SR2_EXTRA3 10

# Şartname Madde 3.4 & 3.5 Emniyet / İrtifa Ayarları
THR_FAILSAFE 1
FS_SHORT_TIMEOUT 1.5
FS_LONG_TIMEOUT 5.0
ALT_HOLD_RTL 6000

# Log / Simülasyon
LOG_BACKEND_TYPE 1
SIM_SPEEDUP 1
EOF
fi

cd "${ARDUPILOT_HOME}"

log "ArduPlane SITL başlatılıyor..."
log "  Vehicle  : ${VEHICLE}"
log "  Frame    : ${FRAME} (JSON model, Gazebo köprüsü)"
log "  Konum    : ${CUSTOM_LOCATION} (teknofest_2026.world & IHAILOS geofence uyumlu)"
log "  Instance : ${INSTANCE}"
log "  MAVLink  : TCP 127.0.0.1:${TCP_BASE} | UDP 127.0.0.1:${UDP_BASE} (IHAILOS) & ${UDP_GCS} (QGC)"
log "  JSON     : Gazebo ArduPilotPlugin → 127.0.0.1:${JSON_PORT}"
log "  NOT      : Önce run_gazebo.sh ile dünyanın açık olduğundan emin olun."

SIM_VEHICLE=(
  sim_vehicle.py
  -v "${VEHICLE}"
  -f "${FRAME}"
  --model JSON
  --custom-location="${CUSTOM_LOCATION}"
  -I "${INSTANCE}"
  --add-param-file "${PARAM_FILE}"
  -w
)

if [[ "${START_MAVPROXY}" -eq 1 ]]; then
  SIM_VEHICLE+=(--console --map)
else
  # MAVProxy yoksa SITL yine TCP 5760 dinler; ana yazılım doğrudan bağlanabilir
  SIM_VEHICLE+=(--no-mavproxy)
fi

# IHAILOS ana yazılımı (14550) ve harici YKI/QGC (14551) için çift UDP çıkışı
SIM_VEHICLE+=(
  --out "udp:127.0.0.1:${UDP_BASE}"
  --out "udp:127.0.0.1:${UDP_GCS}"
)

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  SIM_VEHICLE+=("${EXTRA_ARGS[@]}")
fi

# Gazebo JSON socket ortamı (ArduPilotPlugin fdms ile eşleşmeli, varsayılan 9002)
export SIM_JSON_HOST="${SIM_JSON_HOST:-127.0.0.1}"

log "TCP yer istasyonu / otonomi: 127.0.0.1:${TCP_BASE}"
exec "${SIM_VEHICLE[@]}"
