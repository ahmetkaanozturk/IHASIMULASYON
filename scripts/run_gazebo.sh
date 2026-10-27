#!/usr/bin/env bash
# =============================================================================
# TEKNOFEST 2026 — Gazebo Harmonic dünya + TEKNOFEST Sabit Kanat İHA başlatıcı
# Önkoşul: ./scripts/setup_ardupilot.sh
# Kullanım: ./scripts/run_gazebo.sh [--headless] [--no-spawn] [--verbose]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env
export_gazebo_paths

HEADLESS=0
DO_SPAWN=1
VERBOSE="-v3"
WORLD_FILE="${TEKNOFEST_WORLD:-${WS_ROOT}/worlds/teknofest_2026.world}"
AIRCRAFT_MODEL="${TEKNOFEST_AIRCRAFT_MODEL:-teknofest_fixed_wing}"
# Pist üzerinde kalkış noktası (dünya koordinatları)
SPAWN_X="${TEKNOFEST_SPAWN_X:-10}"
SPAWN_Y="${TEKNOFEST_SPAWN_Y:-0}"
SPAWN_Z="${TEKNOFEST_SPAWN_Z:-0.25}"
SPAWN_YAW="${TEKNOFEST_SPAWN_YAW:-0}"
WORLD_NAME="teknofest_2026"
JSON_PORT="${TEKNOFEST_SITL_JSON_PORT:-9002}"

usage() {
  cat <<EOF
Kullanım: $0 [seçenekler]

  --headless     GUI olmadan (gz sim -s)
  --no-spawn     Uçak modelini spawn etme (yalnızca dünya)
  --verbose      Daha fazla gz log (-v4)
  --world PATH   Dünya dosyası (varsayılan: teknofest_2026.world)
  --help         Bu yardım

Sıra:
  Terminal A: ./scripts/run_gazebo.sh
  Terminal B: ./scripts/run_sitl.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless) HEADLESS=1; shift ;;
    --no-spawn) DO_SPAWN=0; shift ;;
    --verbose) VERBOSE="-v4"; shift ;;
    --world) WORLD_FILE="${2:?}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Bilinmeyen argüman: $1 ( --help )" ;;
  esac
done

require_cmd gz
[[ -f "${WORLD_FILE}" ]] || die "Dünya dosyası yok: ${WORLD_FILE}"

# Model yolları doğrula
for m in pole target_blue_square_4x4 target_red_square_2x2 target_blue_hexagon target_red_triangle teknofest_fixed_wing; do
  [[ -f "${WS_ROOT}/models/${m}/model.sdf" ]] || die "Eksik model: models/${m}/model.sdf"
done

if [[ ! -d "${ARDUPILOT_GAZEBO_HOME}/build" ]]; then
  warn "ardupilot_gazebo build bulunamadı. ArduPilotPlugin yüklenemeyebilir."
fi

PLUGIN_SO="$(find "${ARDUPILOT_GAZEBO_HOME}/build" -name 'libArduPilotPlugin.so' 2>/dev/null | head -n1 || true)"
if [[ -n "${PLUGIN_SO}" ]]; then
  log "ArduPilotPlugin: ${PLUGIN_SO}"
else
  warn "libArduPilotPlugin.so bulunamadı — uçak SITL ile bağlanamayabilir."
fi

log "GZ_SIM_RESOURCE_PATH=${GZ_SIM_RESOURCE_PATH}"
log "Dünya: ${WORLD_FILE}"

# ---------------------------------------------------------------------------
# Arka planda Gazebo başlat; spawn için world servisinin ayağa kalkmasını bekle
# ---------------------------------------------------------------------------
GZ_ARGS=(sim ${VERBOSE} -r)
if [[ "${HEADLESS}" -eq 1 ]]; then
  GZ_ARGS+=(-s)
fi
GZ_ARGS+=("${WORLD_FILE}")

cleanup() {
  if [[ -n "${GZ_PID:-}" ]] && kill -0 "${GZ_PID}" 2>/dev/null; then
    log "Gazebo kapatılıyor (pid=${GZ_PID})..."
    kill "${GZ_PID}" 2>/dev/null || true
    wait "${GZ_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

log "Gazebo başlatılıyor..."
gz "${GZ_ARGS[@]}" &
GZ_PID=$!

wait_for_world() {
  local deadline=$((SECONDS + 90))
  log "Dünya servisi bekleniyor (/world/${WORLD_NAME}/create)..."
  while (( SECONDS < deadline )); do
    if ! kill -0 "${GZ_PID}" 2>/dev/null; then
      die "Gazebo süreci erken çıktı."
    fi
    if gz service -l 2>/dev/null | grep -q "/world/${WORLD_NAME}/create"; then
      log "Dünya hazır."
      return 0
    fi
    sleep 1
  done
  die "Zaman aşımı: /world/${WORLD_NAME}/create servisi görünmedi."
}

spawn_aircraft() {
  local model_uri="model://${AIRCRAFT_MODEL}"
  # Model diskte var mı?
  local found=0
  local IFS=':'
  for p in ${GZ_SIM_RESOURCE_PATH}; do
    if [[ -f "${p}/${AIRCRAFT_MODEL}/model.sdf" ]] || [[ -f "${p}/models/${AIRCRAFT_MODEL}/model.sdf" ]]; then
      found=1
      break
    fi
  done
  unset IFS

  if [[ "${found}" -ne 1 ]]; then
    # Alternatif isimler dene
    for alt in teknofest_fixed_wing zephyr_with_ardupilot zephyr advanced_plane; do
      for p in ${GZ_SIM_RESOURCE_PATH//:/ }; do
        if [[ -f "${p}/${alt}/model.sdf" ]]; then
          AIRCRAFT_MODEL="${alt}"
          model_uri="model://${alt}"
          found=1
          break 2
        fi
      done
    done
  fi

  if [[ "${found}" -ne 1 ]]; then
    warn "Uçak modeli '${AIRCRAFT_MODEL}' bulunamadı. Dünya hedefsiz (yalnızca pist/direk/hedefler) açık."
    warn "ardupilot_gazebo modellerinin GZ_SIM_RESOURCE_PATH içinde olduğundan emin olun."
    return 0
  fi

  log "Uçak spawn: ${model_uri} @ (${SPAWN_X}, ${SPAWN_Y}, ${SPAWN_Z})"

  # EntityFactory proto (protobuf text format)
  local req
  req=$(cat <<EOF
sdf_filename: "${model_uri}"
name: "teknofest_plane"
allow_renaming: true
pose: {
  position: { x: ${SPAWN_X}, y: ${SPAWN_Y}, z: ${SPAWN_Z} }
  orientation: { x: 0, y: 0, z: 0, w: 1 }
}
EOF
)

  if ! gz service -s "/world/${WORLD_NAME}/create" \
      --reqtype gz.msgs.EntityFactory \
      --reptype gz.msgs.Boolean \
      --timeout 10000 \
      --req "${req}"; then
    warn "Spawn servisi başarısız. Model dünya SDF'ine elle eklenebilir; SITL yine de JSON ile dinleyebilir."
  else
    log "Uçak spawn edildi: teknofest_plane"
    log "SITL JSON port beklentisi: ${JSON_PORT} (ArduPilotPlugin model SDF ile eşleşmeli)"
  fi
}

wait_for_world

if [[ "${DO_SPAWN}" -eq 1 ]]; then
  # Render / physics settle
  sleep 2
  spawn_aircraft
fi

log "Gazebo çalışıyor (pid=${GZ_PID}). Durdurmak için Ctrl+C."
log "Şimdi başka terminalde: ./scripts/run_sitl.sh"

# Gazebo sürecini öne al; trap EXIT cleanup yapar
wait "${GZ_PID}"
