#!/usr/bin/env bash
# Ortak yollar ve yardımcı fonksiyonlar — diğer betikler tarafından source edilir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.sh"

# Kurulum kökleri (setup_ardupilot.sh ile uyumlu; env.sh varsa oradan gelir)
: "${TEKNOFEST_HOME:=${HOME}/teknofest_sim}"
: "${ARDUPILOT_HOME:=${TEKNOFEST_HOME}/ardupilot}"
: "${ARDUPILOT_GAZEBO_HOME:=${TEKNOFEST_HOME}/ardupilot_gazebo}"
: "${GAZEBO_MAJOR:=harmonic}"

export WS_ROOT TEKNOFEST_HOME ARDUPILOT_HOME ARDUPILOT_GAZEBO_HOME

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Gerekli komut yok: $1"
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
  else
    warn "env.sh bulunamadı (${ENV_FILE}). Önce ./scripts/setup_ardupilot.sh çalıştırın."
  fi
}

export_gazebo_paths() {
  local models_path="${WS_ROOT}/models"
  local worlds_path="${WS_ROOT}/worlds"
  local ag_models="${ARDUPILOT_GAZEBO_HOME}/models"
  local ag_worlds="${ARDUPILOT_GAZEBO_HOME}/worlds"
  local ag_plugins="${ARDUPILOT_GAZEBO_HOME}/build"

  export GZ_SIM_RESOURCE_PATH="${models_path}${GZ_SIM_RESOURCE_PATH:+:${GZ_SIM_RESOURCE_PATH}}"
  export GZ_SIM_RESOURCE_PATH="${worlds_path}:${GZ_SIM_RESOURCE_PATH}"

  if [[ -d "${ag_models}" ]]; then
    export GZ_SIM_RESOURCE_PATH="${ag_models}:${GZ_SIM_RESOURCE_PATH}"
  fi
  if [[ -d "${ag_worlds}" ]]; then
    export GZ_SIM_RESOURCE_PATH="${ag_worlds}:${GZ_SIM_RESOURCE_PATH}"
  fi

  # Sistem eklenti yolları + ardupilot_gazebo build
  if [[ -d "${ag_plugins}" ]]; then
    export GZ_SIM_SYSTEM_PLUGIN_PATH="${ag_plugins}${GZ_SIM_SYSTEM_PLUGIN_PATH:+:${GZ_SIM_SYSTEM_PLUGIN_PATH}}"
  fi
  # Debian/Ubuntu gz-sim eklenti dizinleri
  for d in /usr/lib/x86_64-linux-gnu/gz-sim-*/plugins /usr/lib/x86_64-linux-gnu/gz-sim-8/plugins; do
    if [[ -d "${d}" ]]; then
      export GZ_SIM_SYSTEM_PLUGIN_PATH="${d}${GZ_SIM_SYSTEM_PLUGIN_PATH:+:${GZ_SIM_SYSTEM_PLUGIN_PATH}}"
    fi
  done

  export LD_LIBRARY_PATH="${ag_plugins}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
}
