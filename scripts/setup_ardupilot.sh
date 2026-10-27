#!/usr/bin/env bash
# =============================================================================
# TEKNOFEST 2026 — ArduPilot SITL + Gazebo Harmonic + ardupilot_gazebo kurulumu
# Hedef OS: Ubuntu 22.04 LTS (x86_64)
# Kullanım:  chmod +x scripts/*.sh && ./scripts/setup_ardupilot.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

TEKNOFEST_HOME="${TEKNOFEST_HOME:-${HOME}/teknofest_sim}"
ARDUPILOT_HOME="${TEKNOFEST_HOME}/ardupilot"
ARDUPILOT_GAZEBO_HOME="${TEKNOFEST_HOME}/ardupilot_gazebo"
GAZEBO_MAJOR="harmonic"
JOBS="$(nproc)"
NONINTERACTIVE="${NONINTERACTIVE:-1}"

export DEBIAN_FRONTEND=noninteractive
export TEKNOFEST_HOME ARDUPILOT_HOME ARDUPILOT_GAZEBO_HOME

check_os() {
  log "İşletim sistemi kontrolü..."
  if [[ ! -f /etc/os-release ]]; then
    die "Bu betik yalnızca Linux (Ubuntu 22.04) içindir."
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    die "Desteklenen OS: Ubuntu. Algılanan: ${ID}"
  fi
  if [[ "${VERSION_ID}" != "22.04" ]]; then
    warn "Bu betik Ubuntu 22.04 için yazıldı (algılanan: ${VERSION_ID}). Devam ediliyor..."
  fi
  if [[ "$(uname -m)" != "x86_64" ]]; then
    die "Yalnızca x86_64 desteklenir."
  fi
  log "OS OK: Ubuntu ${VERSION_ID} $(uname -m)"
}

install_base_packages() {
  log "Temel paketler kuruluyor..."
  sudo apt-get update -y
  sudo apt-get install -y \
    git \
    curl \
    wget \
    lsb-release \
    gnupg \
    ca-certificates \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-wxgtk4.0 \
    python3-matplotlib \
    python3-numpy \
    python3-opencv \
    python3-lxml \
    python3-yaml \
    python3-serial \
    ccache \
    gawk \
    rsync \
    libtool \
    libxml2-dev \
    libxslt1-dev \
    rapidjson-dev \
    libopencv-dev
}

install_gazebo_harmonic() {
  log "Gazebo Harmonic kurulumu..."
  if command -v gz >/dev/null 2>&1; then
    local ver
    ver="$(gz sim --versions 2>/dev/null | head -n1 || true)"
    log "gz zaten kurulu (sürüm bilgisi: ${ver:-bilinmiyor}). Atlanıyor."
    return 0
  fi

  sudo mkdir -p /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/pkgs-osrf.gpg ]]; then
    curl -fsSL https://packages.osrfoundation.org/gazebo.gpg \
      | sudo tee /etc/apt/keyrings/pkgs-osrf.gpg >/dev/null
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/pkgs-osrf.gpg] \
http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/gazebo-stable.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y gz-harmonic

  require_cmd gz
  log "Gazebo Harmonic kuruldu: $(gz sim --versions 2>/dev/null | head -n1 || echo OK)"
}

clone_ardupilot() {
  log "ArduPilot klonlanıyor / güncelleniyor..."
  mkdir -p "${TEKNOFEST_HOME}"
  if [[ ! -d "${ARDUPILOT_HOME}/.git" ]]; then
    git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git "${ARDUPILOT_HOME}"
  else
    git -C "${ARDUPILOT_HOME}" fetch --prune
    git -C "${ARDUPILOT_HOME}" pull --ff-only || warn "ardupilot pull başarısız; mevcut sürüm kullanılacak."
    git -C "${ARDUPILOT_HOME}" submodule update --init --recursive
  fi
}

install_ardupilot_prereqs() {
  log "ArduPilot önkoşulları (install-prereqs-ubuntu.sh)..."
  local prereq="${ARDUPILOT_HOME}/Tools/environment_install/install-prereqs-ubuntu.sh"
  [[ -f "${prereq}" ]] || die "Bulunamadı: ${prereq}"
  # -y: etkileşimsiz
  bash "${prereq}" -y

  # PATH: waf / sim_vehicle.py kullanıcı local bin
  export PATH="${HOME}/.local/bin:${PATH}"
  hash -r || true

  # MAVProxy + pymavlink (SITL yer istasyonu)
  pip3 install --user --upgrade pip
  pip3 install --user --upgrade MAVProxy pymavlink dronekit future
}

build_ardupilot_sitl() {
  log "ArduPlane SITL derleniyor (waf)..."
  cd "${ARDUPILOT_HOME}"
  export PATH="${HOME}/.local/bin:${PATH}"

  # gcc/g++ seçimi install-prereqs sonrası hazır olmalı
  ./waf distclean || true
  ./waf configure --board sitl
  ./waf plane -j"${JOBS}"

  [[ -x "${ARDUPILOT_HOME}/build/sitl/bin/arduplane" ]] \
    || die "arduplane ikilisi üretilmedi."
  log "ArduPlane SITL derleme tamam: build/sitl/bin/arduplane"
}

clone_and_build_ardupilot_gazebo() {
  log "ardupilot_gazebo klonlanıyor / derleniyor..."
  if [[ ! -d "${ARDUPILOT_GAZEBO_HOME}/.git" ]]; then
    git clone https://github.com/ArduPilot/ardupilot_gazebo.git "${ARDUPILOT_GAZEBO_HOME}"
  else
    git -C "${ARDUPILOT_GAZEBO_HOME}" pull --ff-only || warn "ardupilot_gazebo pull başarısız."
  fi

  # Harmonic için gz-sim-8 bağımlılıkları + Python kamera köprüsü bağlamaları
  sudo apt-get install -y \
    libgz-sim8-dev \
    python3-gz-transport13 \
    python3-gz-msgs10 \
    rapidjson-dev \
    libopencv-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    || warn "Bazı libgz paketleri kurulamadı; cmake aşaması doğrulayacak."

  mkdir -p "${ARDUPILOT_GAZEBO_HOME}/build"
  cd "${ARDUPILOT_GAZEBO_HOME}/build"
  cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
  make -j"${JOBS}"

  local plugin
  plugin="$(find "${ARDUPILOT_GAZEBO_HOME}/build" -name 'libArduPilotPlugin.so' 2>/dev/null | head -n1 || true)"
  if [[ -z "${plugin}" ]]; then
    die "ArduPilotPlugin derlenemedi (libArduPilotPlugin.so yok)."
  fi
  log "ArduPilot Gazebo eklentisi: ${plugin}"
}

write_env_file() {
  log "env.sh yazılıyor: ${ENV_FILE}"
  cat > "${ENV_FILE}" <<EOF
# Otomatik üretildi — setup_ardupilot.sh ($(date -Iseconds))
# Bu dosyayı elle düzenleyebilirsiniz.
export TEKNOFEST_HOME="${TEKNOFEST_HOME}"
export ARDUPILOT_HOME="${ARDUPILOT_HOME}"
export ARDUPILOT_GAZEBO_HOME="${ARDUPILOT_GAZEBO_HOME}"
export WS_ROOT="${WS_ROOT}"
export GAZEBO_MAJOR="${GAZEBO_MAJOR}"

export PATH="\${HOME}/.local/bin:\${ARDUPILOT_HOME}/Tools/autotest:\${PATH}"

# Gazebo kaynak / eklenti yolları
export GZ_SIM_RESOURCE_PATH="${WS_ROOT}/models:${WS_ROOT}/worlds:\${ARDUPILOT_GAZEBO_HOME}/models:\${ARDUPILOT_GAZEBO_HOME}/worlds\${GZ_SIM_RESOURCE_PATH:+:\${GZ_SIM_RESOURCE_PATH}}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="\${ARDUPILOT_GAZEBO_HOME}/build\${GZ_SIM_SYSTEM_PLUGIN_PATH:+:\${GZ_SIM_SYSTEM_PLUGIN_PATH}}"
export LD_LIBRARY_PATH="\${ARDUPILOT_GAZEBO_HOME}/build\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"

# MAVLink — ana otonomi yazılımı ile çakışmayan localhost portları
export TEKNOFEST_MAVLINK_TCP="127.0.0.1:5760"
export TEKNOFEST_MAVLINK_UDP="127.0.0.1:14550"
export TEKNOFEST_SITL_JSON_PORT="9002"

# SITL örnek parametre / varsayılan frame (TEKNOFEST Sabit Kanat)
export TEKNOFEST_AIRCRAFT_MODEL="teknofest_fixed_wing"
export TEKNOFEST_SITL_VEHICLE="ArduPlane"
export TEKNOFEST_SITL_FRAME="plane"
export TEKNOFEST_SITL_LOCATION="39.925533,32.866287,890,90"
export TEKNOFEST_WORLD="${WS_ROOT}/worlds/teknofest_2026.world"
EOF
}

print_summary() {
  cat <<EOF

=============================================================================
 Kurulum tamamlandı.
=============================================================================
  Çalışma alanı : ${WS_ROOT}
  ArduPilot     : ${ARDUPILOT_HOME}
  Gazebo eklenti: ${ARDUPILOT_GAZEBO_HOME}
  Dünya         : ${WS_ROOT}/worlds/teknofest_2026.world
  Ortam dosyası : ${ENV_FILE}

 Çalıştırma sırası (iki ayrı terminal):
   1) ./scripts/run_gazebo.sh
   2) ./scripts/run_sitl.sh

 MAVLink:
   TCP  ${TEKNOFEST_MAVLINK_TCP:-127.0.0.1:5760}
   UDP  ${TEKNOFEST_MAVLINK_UDP:-127.0.0.1:14550}
=============================================================================
EOF
}

main() {
  check_os
  install_base_packages
  install_gazebo_harmonic
  clone_ardupilot
  install_ardupilot_prereqs
  build_ardupilot_sitl
  clone_and_build_ardupilot_gazebo
  write_env_file
  print_summary
}

main "$@"
