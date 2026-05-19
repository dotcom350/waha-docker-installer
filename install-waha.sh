#!/bin/bash

# ============================================================
#  WAHA Docker Installer / Uninstaller — Interactive Setup
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "  ██╗    ██╗ █████╗ ██╗  ██╗ █████╗ "
  echo "  ██║    ██║██╔══██╗██║  ██║██╔══██╗"
  echo "  ██║ █╗ ██║███████║███████║███████║"
  echo "  ██║███╗██║██╔══██║██╔══██║██╔══██║"
  echo "  ╚███╔███╔╝██║  ██║██║  ██║██║  ██║"
  echo "   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
  echo -e "${RESET}"
  echo -e "${BOLD}  WhatsApp HTTP API — Docker Installer${RESET}"
  echo -e "  ${YELLOW}https://waha.devlike.pro${RESET}"
  echo ""
}

step() {
  echo ""
  echo -e "${BLUE}${BOLD}▶ PASO $1: $2${RESET}"
  echo -e "  ${YELLOW}$3${RESET}"
  echo ""
}

success() { echo -e "  ${GREEN}✔ $1${RESET}"; }
info()    { echo -e "  ${CYAN}ℹ $1${RESET}"; }
warn()    { echo -e "  ${YELLOW}⚠ $1${RESET}"; }

error_exit() {
  echo -e "  ${RED}✘ ERROR: $1${RESET}"
  exit 1
}

prompt_continue() {
  echo ""
  read -rp "  $(echo -e "${BOLD}Presiona [Enter] para continuar...${RESET}")" _
}

gen_password() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' \
    || openssl rand -hex 16 2>/dev/null \
    || head -c 32 /dev/urandom | xxd -p | head -c 32
}

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    warn "No estás corriendo como root. Algunos pasos pueden fallar."
    warn "Se recomienda: sudo bash waha.sh"
    prompt_continue
  fi
}

get_server_ip() {
  SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}')
  echo "$SERVER_IP"
}

# ════════════════════════════════════════════════════════════
#  MENÚ PRINCIPAL
# ════════════════════════════════════════════════════════════
main_menu() {
  print_banner
  echo -e "  ${BOLD}¿Qué deseas hacer?${RESET}"
  echo ""
  echo -e "  ${GREEN}[1]${RESET} 🚀 Instalar WAHA"
  echo -e "  ${RED}[2]${RESET} ❌ ${RED}Desinstalar WAHA${RESET}"
  echo -e "  ${CYAN}[3]${RESET} 📋 ${CYAN}Ver estado del servicio${RESET}"
  echo -e "  ${BLUE}[4]${RESET} 🛠️  ${BLUE}Reparar parche Core${RESET}"
  echo -e "  ${YELLOW}[0]${RESET} 🟡  ${YELLOW}Salir${RESET}"
  echo ""
  read -rp "  Elige una opción [1]: " MENU_CHOICE
  MENU_CHOICE="${MENU_CHOICE:-1}"

  case "$MENU_CHOICE" in
    1) install_waha ;;
    2) uninstall_waha ;;
    3) status_waha ;;
    4) repair_waha_patch ;;
    0) echo "" && echo -e "  ${CYAN}Hasta luego.${RESET}" && echo "" && exit 0 ;;
    *) warn "Opción inválida." && sleep 1 && main_menu ;;
  esac
}

# ════════════════════════════════════════════════════════════
#  ESTADO DEL SERVICIO
# ════════════════════════════════════════════════════════════
status_waha() {
  print_banner
  echo -e "  ${BOLD}📋 Estado del servicio WAHA${RESET}"
  echo ""

  # Buscar directorio de instalación
  DEFAULT_DIR="$HOME/waha"
  read -rp "  Directorio de instalación [${DEFAULT_DIR}]: " STATUS_DIR
  STATUS_DIR="${STATUS_DIR:-$DEFAULT_DIR}"

  if [[ ! -f "${STATUS_DIR}/docker-compose.yaml" ]]; then
    warn "No se encontró una instalación de WAHA en ${STATUS_DIR}"
    prompt_continue
    main_menu
    return
  fi

  cd "$STATUS_DIR"

  echo ""
  echo -e "${CYAN}${BOLD}  ── Contenedores ──────────────────────────────────────${RESET}"
  docker compose ps
  echo ""
  echo -e "${CYAN}${BOLD}  ── Últimas 20 líneas de logs ─────────────────────────${RESET}"
  docker compose logs --tail=20
  echo ""

  # Leer credenciales del .env si existe
  if [[ -f "${STATUS_DIR}/.env" ]]; then
    SAVED_PORT=$(grep -oP '(?<=:)\d+(?=:3000|$)' "${STATUS_DIR}/docker-compose.yaml" 2>/dev/null | head -1 || echo "3000")
    SAVED_PORT="${SAVED_PORT:-3000}"
    HEALTH=$(curl -s --max-time 3 "http://localhost:${SAVED_PORT}/api/health" 2>/dev/null || echo "no responde")

    echo -e "${CYAN}${BOLD}  ── Health Check ───────────────────────────────────────${RESET}"
    if echo "$HEALTH" | grep -qi "ok\|true\|health"; then
      echo -e "  ${GREEN}✔ Servicio respondiendo en http://localhost:${SAVED_PORT}${RESET}"
    else
      echo -e "  ${YELLOW}⚠ El servicio no responde en http://localhost:${SAVED_PORT}${RESET}"
    fi
    echo ""
  fi

  prompt_continue
  main_menu
}

# ════════════════════════════════════════════════════════════
#  DESINSTALACIÓN
# ════════════════════════════════════════════════════════════
repair_waha_patch() {
  print_banner
  echo -e "  ${BOLD}🛠 Reparar parche WAHA Core${RESET}"
  echo ""

  DEFAULT_DIR="$HOME/waha"
  read -rp "  Directorio de instalación [${DEFAULT_DIR}]: " REPAIR_DIR
  REPAIR_DIR="${REPAIR_DIR:-$DEFAULT_DIR}"

  if [[ ! -f "${REPAIR_DIR}/docker-compose.yaml" ]]; then
    warn "No se encontró docker-compose.yaml en ${REPAIR_DIR}"
    prompt_continue
    main_menu
    return
  fi

  if [[ ! -f "${REPAIR_DIR}/Dockerfile.waha-core-patch" || ! -f "${REPAIR_DIR}/patch-waha-core.js" ]]; then
    warn "No se encontraron todos los archivos del parche en ${REPAIR_DIR}; se intentarán regenerar desde este instalador."
  fi

  cd "$REPAIR_DIR"
  if [[ -f ".env" ]]; then
    SAVED_API_KEY=$(grep '^WAHA_API_KEY=' .env | tail -1 | cut -d= -f2-)
    if [[ -n "$SAVED_API_KEY" ]]; then
      grep -q '^WAHA_API_KEY_PLAIN=' .env || echo "WAHA_API_KEY_PLAIN=${SAVED_API_KEY}" >> .env
      grep -q '^WHATSAPP_API_KEY=' .env || echo "WHATSAPP_API_KEY=${SAVED_API_KEY}" >> .env
    fi
  fi
  PATCHED_IMAGE=$(grep 'image:' docker-compose.yaml | awk '{print $2}' | tr -d '"' | head -1)
  BASE_IMAGE=$(grep '^ARG WAHA_BASE_IMAGE=' Dockerfile.waha-core-patch 2>/dev/null | cut -d= -f2-)

  [[ -z "$PATCHED_IMAGE" ]] && error_exit "No se pudo detectar la imagen parcheada en docker-compose.yaml."
  [[ -z "$BASE_IMAGE" ]] && BASE_IMAGE="devlikeapro/waha"
  if ! echo "$PATCHED_IMAGE" | grep -q '^waha-core-session-patched:'; then
    BASE_IMAGE="$PATCHED_IMAGE"
    PATCHED_IMAGE="waha-core-session-patched:$(echo "${BASE_IMAGE}" | tr '/:' '--')"
    sed -i "0,/image:.*/s|image:.*|image: ${PATCHED_IMAGE}|" docker-compose.yaml
  fi

  SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
  if [[ -f "$SCRIPT_PATH" ]]; then
    awk "/cat > patch-waha-core.js <<'EOF'/{flag=1;next} flag && /^EOF$/{flag=0;exit} flag{print}" "$SCRIPT_PATH" > patch-waha-core.js
    cat > Dockerfile.waha-core-patch <<EOF
ARG WAHA_BASE_IMAGE=${BASE_IMAGE}
FROM \${WAHA_BASE_IMAGE}
COPY patch-waha-core.js /tmp/patch-waha-core.js
RUN node /tmp/patch-waha-core.js && rm /tmp/patch-waha-core.js
EOF
    success "Archivos del parche actualizados desde ${SCRIPT_PATH}"
  else
    warn "No se pudo localizar el script actual para refrescar patch-waha-core.js; se usará el parche existente."
  fi

  info "Imagen base: ${BASE_IMAGE}"
  info "Imagen parcheada: ${PATCHED_IMAGE}"
  docker pull "${BASE_IMAGE}" || error_exit "No se pudo descargar la imagen base."
  docker build \
    -f Dockerfile.waha-core-patch \
    --build-arg "WAHA_BASE_IMAGE=${BASE_IMAGE}" \
    -t "${PATCHED_IMAGE}" . || error_exit "No se pudo reconstruir la imagen parcheada."
  docker compose up -d || error_exit "No se pudo reiniciar WAHA con la imagen reparada."

  success "Parche reparado y servicio reiniciado."
  prompt_continue
  main_menu
}

uninstall_waha() {
  print_banner
  echo -e "  ${RED}${BOLD}🗑  DESINSTALACIÓN DE WAHA${RESET}"
  echo ""
  echo -e "  ${YELLOW}Este proceso detendrá y eliminará WAHA de tu servidor.${RESET}"
  echo ""

  # ── Paso U1: Directorio ───────────────────────────────────
  DEFAULT_DIR="$HOME/waha"
  read -rp "  Directorio de instalación [${DEFAULT_DIR}]: " UNINSTALL_DIR
  UNINSTALL_DIR="${UNINSTALL_DIR:-$DEFAULT_DIR}"

  if [[ ! -f "${UNINSTALL_DIR}/docker-compose.yaml" ]]; then
    warn "No se encontró docker-compose.yaml en ${UNINSTALL_DIR}"
    warn "Verifica que el directorio sea correcto."
    prompt_continue
    main_menu
    return
  fi

  # Leer imagen usada
  USED_IMAGES=$(grep 'image:' "${UNINSTALL_DIR}/docker-compose.yaml" | awk '{print $2}' | tr -d '"' | sort -u)
  info "Instalación encontrada en: ${UNINSTALL_DIR}"
  info "Imagen detectada: ${USED_IMAGES:-desconocida}"

  # ── Paso U2: Elegir nivel de desinstalación ───────────────
  echo ""
  echo -e "  ${BOLD}¿Qué deseas eliminar?${RESET}"
  echo ""
  echo -e "  ${YELLOW}[1]${RESET} Soft — Solo detener y eliminar contenedores"
  echo -e "  ${YELLOW}[2]${RESET} Normal — Contenedores + archivos de configuración (.env, compose)"
  echo -e "  ${RED}[3]${RESET} Full  — TODO: contenedores, archivos, volúmenes (sesiones y media) e imagen Docker"
  echo ""
  read -rp "  Elige nivel de desinstalación [2]: " UNINSTALL_LEVEL
  UNINSTALL_LEVEL="${UNINSTALL_LEVEL:-2}"

  # ── Confirmación ──────────────────────────────────────────
  echo ""
  case "$UNINSTALL_LEVEL" in
    1) LEVEL_DESC="Soft — solo detener contenedores" ;;
    2) LEVEL_DESC="Normal — contenedores + archivos de configuración" ;;
    3) LEVEL_DESC="${RED}${BOLD}Full — ELIMINA TODO incluyendo sesiones de WhatsApp${RESET}" ;;
    *) warn "Opción inválida. Usando nivel Normal (2)." && UNINSTALL_LEVEL=2 && LEVEL_DESC="Normal" ;;
  esac

  echo -e "  ${BOLD}Nivel seleccionado:${RESET} $(echo -e $LEVEL_DESC)"
  echo -e "  ${BOLD}Directorio:${RESET}        ${UNINSTALL_DIR}"
  echo ""
  echo -e "  ${RED}${BOLD}⚠ Esta acción no se puede deshacer.${RESET}"
  echo ""
  read -rp "  ¿Confirmas la desinstalación? Escribe 'si' para continuar: " CONFIRM
  [[ "$CONFIRM" != "si" && "$CONFIRM" != "sí" ]] && \
    echo -e "\n  ${CYAN}Desinstalación cancelada.${RESET}\n" && \
    prompt_continue && main_menu && return

  echo ""
  echo -e "${BLUE}${BOLD}▶ Ejecutando desinstalación nivel ${UNINSTALL_LEVEL}...${RESET}"
  echo ""

  cd "$UNINSTALL_DIR"

  # ── Detener y eliminar contenedores ───────────────────────
  info "Deteniendo contenedores..."
  if [[ "$UNINSTALL_LEVEL" == "3" ]]; then
    docker compose down --volumes --remove-orphans 2>/dev/null || true
    success "Contenedores detenidos y volúmenes eliminados."
  else
    docker compose down --remove-orphans 2>/dev/null || true
    success "Contenedores detenidos."
  fi

  # ── Nivel 2+: Eliminar archivos de configuración ─────────
  if [[ "$UNINSTALL_LEVEL" -ge 2 ]]; then
    info "Eliminando archivos de configuración..."
    rm -f "${UNINSTALL_DIR}/.env"
    rm -f "${UNINSTALL_DIR}/docker-compose.yaml"
    rm -f "${UNINSTALL_DIR}/waha-credentials.txt"
    success "Archivos de configuración eliminados."

    # Si el directorio quedó vacío, eliminarlo
    if [[ -z "$(ls -A "${UNINSTALL_DIR}" 2>/dev/null)" ]]; then
      cd "$HOME"
      rmdir "$UNINSTALL_DIR" 2>/dev/null && success "Directorio ${UNINSTALL_DIR} eliminado (estaba vacío)."
    else
      warn "El directorio ${UNINSTALL_DIR} aún contiene archivos y no fue eliminado."
      info "Contenido restante:"
      ls -la "$UNINSTALL_DIR"
    fi
  fi

  # ── Nivel 3: Eliminar imagen Docker ───────────────────────
  if [[ "$UNINSTALL_LEVEL" == "3" && -n "$USED_IMAGES" ]]; then
    while IFS= read -r USED_IMAGE; do
      [[ -z "$USED_IMAGE" ]] && continue
      info "Eliminando imagen Docker: ${USED_IMAGE}..."
      docker rmi "$USED_IMAGE" 2>/dev/null && success "Imagen ${USED_IMAGE} eliminada." \
        || warn "No se pudo eliminar la imagen (puede estar en uso por otro contenedor)."
    done <<< "$USED_IMAGES"

    # Limpiar imágenes dangling
    info "Limpiando imágenes huérfanas..."
    docker image prune -f 2>/dev/null && success "Imágenes huérfanas eliminadas." || true

    # Cerrar sesión de Docker Hub si era WAHA Plus
    if echo "$USED_IMAGES" | grep -q "plus"; then
      info "Cerrando sesión de Docker registry (WAHA Plus)..."
      docker logout 2>/dev/null && success "Sesión cerrada." || true
    fi
  fi

  # ── Resumen de desinstalación ─────────────────────────────
  clear
  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}║          ✅  WAHA DESINSTALADO CORRECTAMENTE             ║${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  case "$UNINSTALL_LEVEL" in
    1)
      echo -e "  ${GREEN}✔${RESET} Contenedores detenidos y eliminados"
      echo -e "  ${YELLOW}–${RESET} Archivos de configuración conservados en: ${UNINSTALL_DIR}"
      echo -e "  ${YELLOW}–${RESET} Volúmenes Docker conservados (sesiones y media intactas)"
      echo -e "  ${YELLOW}–${RESET} Imagen Docker conservada"
      echo ""
      info "Para reinstalar: cd ${UNINSTALL_DIR} && docker compose up -d"
      ;;
    2)
      echo -e "  ${GREEN}✔${RESET} Contenedores detenidos y eliminados"
      echo -e "  ${GREEN}✔${RESET} Archivos de configuración eliminados"
      echo -e "  ${YELLOW}–${RESET} Volúmenes Docker conservados (sesiones y media intactas)"
      echo -e "  ${YELLOW}–${RESET} Imagen Docker conservada"
      echo ""
      info "Los volúmenes Docker aún existen. Para eliminarlos manualmente:"
      info "docker volume ls | grep waha"
      info "docker volume rm <nombre_volumen>"
      ;;
    3)
      echo -e "  ${GREEN}✔${RESET} Contenedores detenidos y eliminados"
      echo -e "  ${GREEN}✔${RESET} Archivos de configuración eliminados"
      echo -e "  ${GREEN}✔${RESET} Volúmenes Docker eliminados (sesiones y media)"
      echo -e "  ${GREEN}✔${RESET} Imagen Docker eliminada"
      echo ""
      echo -e "  ${CYAN}WAHA ha sido completamente removido del sistema.${RESET}"
      ;;
  esac

  echo ""
  prompt_continue
  main_menu
}

# ════════════════════════════════════════════════════════════
#  INSTALACIÓN
# ════════════════════════════════════════════════════════════
install_waha() {
  print_banner
  echo -e "  Este script instalará ${BOLD}WAHA (WhatsApp HTTP API)${RESET} en Docker."
  echo -e "  Guiará el proceso paso a paso y al final mostrará las credenciales."
  echo ""
  check_root

  # ── Paso 1: Directorio ────────────────────────────────────
  step "1" "Directorio de instalación" "¿Dónde deseas instalar WAHA?"

  DEFAULT_DIR="$HOME/waha"
  read -rp "  Directorio [${DEFAULT_DIR}]: " INSTALL_DIR
  INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"

  if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/docker-compose.yaml" ]]; then
    warn "Ya existe una instalación en $INSTALL_DIR"
    read -rp "  ¿Sobreescribir? (s/n) [n]: " OVERWRITE
    OVERWRITE="${OVERWRITE:-n}"
    [[ "$OVERWRITE" != "s" && "$OVERWRITE" != "S" ]] && \
      echo -e "\n  ${CYAN}Instalación cancelada.${RESET}\n" && \
      prompt_continue && main_menu && return
  fi

  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  success "Directorio: $INSTALL_DIR"

  # ── Paso 2: Instalar Docker ───────────────────────────────
  step "2" "Instalar Docker" "Verificando e instalando Docker y Docker Compose..."

  if ! command -v docker &>/dev/null; then
    info "Instalando Docker..."
    apt-get update -qq
    apt-get upgrade -y -qq
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    apt-get install -y -qq docker-compose-plugin
    success "Docker instalado correctamente."
  else
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    success "Docker ya instalado: v${DOCKER_VERSION}"
  fi

  if ! docker compose version &>/dev/null; then
    apt-get install -y -qq docker-compose-plugin
  fi
  success "Docker Compose disponible."

  # ── Paso 3: Edición ───────────────────────────────────────
  step "3" "Edición de WAHA" "Selecciona la versión que deseas instalar:"

  echo "  [1] 🔓 WAHA Core    — Gratis, parcheada y con sesiones ilimitadas (recomendado)"
  echo "  [2] WAHA Plus    — De pago, requiere API key de devlikeapro"
  echo "  [3] WAHA ARM     — Para servidores ARM (Raspberry Pi, Apple M1/M2)"
  echo ""
  read -rp "  Elige una opción [1]: " EDITION_CHOICE
  EDITION_CHOICE="${EDITION_CHOICE:-1}"

  case "$EDITION_CHOICE" in
    1) WAHA_IMAGE="devlikeapro/waha";      EDITION_NAME="WAHA Core" ;;
    2)
      WAHA_IMAGE="devlikeapro/waha-plus";  EDITION_NAME="WAHA Plus"
      echo ""
      read -rp "  Ingresa tu API key de WAHA Plus: " WAHA_PLUS_KEY
      [[ -z "$WAHA_PLUS_KEY" ]] && error_exit "API key requerida para WAHA Plus."
      echo "$WAHA_PLUS_KEY" | docker login -u devlikeapro --password-stdin \
        || error_exit "Login fallido. Verifica tu API key."
      success "Login exitoso."
      ;;
    3) WAHA_IMAGE="devlikeapro/waha:arm";  EDITION_NAME="WAHA ARM" ;;
    *)
      warn "Opción inválida. Usando WAHA Core."
      WAHA_IMAGE="devlikeapro/waha"; EDITION_NAME="WAHA Core"
      ;;
  esac

  success "Edición: ${EDITION_NAME} (${WAHA_IMAGE})"

  SOURCE_WAHA_IMAGE="${WAHA_IMAGE}"
  PATCH_CORE_IMAGE="0"
  if [[ "$EDITION_CHOICE" != "2" ]]; then
    PATCH_CORE_IMAGE="1"
    PATCHED_WAHA_IMAGE="waha-core-session-patched:$(echo "${WAHA_IMAGE}" | tr '/:' '--')"
    WAHA_IMAGE="${PATCHED_WAHA_IMAGE}"
    info "Se creara una imagen local parcheada para permitir nombres de sesion distintos a 'default'."
  fi

  # ── Paso 4: Red ───────────────────────────────────────────
  step "4" "Configuración de red" "Define el puerto y acceso al servicio."

  read -rp "  Puerto para WAHA [3000]: " WAHA_PORT
  WAHA_PORT="${WAHA_PORT:-3000}"

  echo ""
  echo "  [1] Solo localhost (127.0.0.1:${WAHA_PORT}) — Más seguro"
  echo "  [2] Todas las IPs  (0.0.0.0:${WAHA_PORT})  — Acceso externo directo"
  echo ""
  read -rp "  Elige una opción [1]: " BIND_CHOICE
  BIND_CHOICE="${BIND_CHOICE:-1}"

  if [[ "$BIND_CHOICE" == "2" ]]; then
    PORT_BINDING="${WAHA_PORT}:3000"
    warn "El servicio estará expuesto públicamente en el puerto ${WAHA_PORT}."
  else
    PORT_BINDING="127.0.0.1:${WAHA_PORT}:3000"
    info "Solo accesible desde localhost."
  fi

  success "Puerto: ${PORT_BINDING}"

  # ── Paso 5: Credenciales ──────────────────────────────────
  step "5" "Generando credenciales seguras" "Creando contraseñas aleatorias..."

  DASHBOARD_USER="admin"
  DASHBOARD_PASS=$(gen_password)
  API_KEY=$(gen_password)
  SWAGGER_PASS=$(gen_password)
  success "Credenciales generadas."

  # ── Paso 6: Archivos de configuración ─────────────────────
  step "6" "Creando archivos de configuración" "Generando .env y docker-compose.yaml..."

  SERVER_IP=$(get_server_ip)

  if [[ "$BIND_CHOICE" == "2" ]]; then
    BASE_URL="http://${SERVER_IP}:${WAHA_PORT}"
  else
    BASE_URL="http://localhost:${WAHA_PORT}"
  fi

  cat > .env <<EOF
# WAHA — Generado automáticamente
# Fecha: $(date '+%Y-%m-%d %H:%M:%S')

WAHA_DASHBOARD_USERNAME=${DASHBOARD_USER}
WAHA_DASHBOARD_PASSWORD=${DASHBOARD_PASS}
WAHA_API_KEY=${API_KEY}
WAHA_API_KEY_PLAIN=${API_KEY}
WHATSAPP_API_KEY=${API_KEY}
WHATSAPP_SWAGGER_USERNAME=${DASHBOARD_USER}
WHATSAPP_SWAGGER_PASSWORD=${SWAGGER_PASS}
WAHA_BASE_URL=${BASE_URL}
EOF
  success ".env creado."

  if [[ "$PATCH_CORE_IMAGE" == "1" ]]; then
    cat > Dockerfile.waha-core-patch <<EOF
ARG WAHA_BASE_IMAGE=${SOURCE_WAHA_IMAGE}
FROM \${WAHA_BASE_IMAGE}
COPY patch-waha-core.js /tmp/patch-waha-core.js
RUN node /tmp/patch-waha-core.js && rm /tmp/patch-waha-core.js
EOF

    cat > patch-waha-core.js <<'EOF'
const fs = require('fs');
const path = require('path');

function findFile(dir, name, depth = 0) {
  if (depth > 8 || !fs.existsSync(dir)) {
    return null;
  }

  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const current = path.join(dir, entry.name);
    if (entry.isFile() && entry.name === name) {
      return current;
    }
    if (
      entry.isDirectory() &&
      !['node_modules', '.git', '.sessions', 'media'].includes(entry.name)
    ) {
      const found = findFile(current, name, depth + 1);
      if (found) {
        return found;
      }
    }
  }
  return null;
}

const roots = ['/app', '/usr/src/app', '/opt/app'];
let file = null;
for (const root of roots) {
  file = findFile(root, 'manager.core.js');
  if (file) {
    break;
  }
}

if (!file) {
  throw new Error('No se encontro manager.core.js dentro de la imagen WAHA.');
}

let source = fs.readFileSync(file, 'utf8');
let patched = source.replace(
  /onlyDefault\(name\)\s*\{\s*if\s*\(name\s*!==\s*this\.DEFAULT\)\s*\{[\s\S]*?throw new OnlyDefaultSessionIsAllowed\(name\);[\s\S]*?\}\s*\}/m,
  'onlyDefault(name) {\n        return;\n    }',
);

const multiSessionPatch = `

// WAHA Core community patch: in-memory multi-session manager.
(() => {
  const PATCH_FLAG = '__wahaCoreCommunityMultiSessionPatch';
  const managerClass = exports.SessionManagerCore;
  if (!managerClass || managerClass.prototype[PATCH_FLAG]) {
    return;
  }

  const STOPPED = null;
  const REMOVED = undefined;

  function ensureState(manager) {
    if (!manager.sessions) {
      manager.sessions = new Map();
    }
    if (!manager.sessionConfigs) {
      manager.sessionConfigs = new Map();
    }
    if (!manager.sessionStates) {
      manager.sessionStates = new Map();
      manager.sessionStates.set(manager.DEFAULT || 'default', STOPPED);
    }
  }

  function sessionConfig(manager, name) {
    ensureState(manager);
    return manager.sessionConfigs.get(name) ?? null;
  }

  function sessionsObject(manager) {
    ensureState(manager);
    const sessions = {};
    for (const [name, session] of manager.sessions.entries()) {
      sessions[name] = session;
    }
    return sessions;
  }

  managerClass.prototype[PATCH_FLAG] = true;

  managerClass.prototype.onlyDefault = function onlyDefault(name) {
    return;
  };

  managerClass.prototype.beforeApplicationShutdown = async function beforeApplicationShutdown(signal) {
    ensureState(this);
    for (const name of Array.from(this.sessions.keys())) {
      await this.stop(name, true);
    }
    this.stopEvents();
    await this.engineBootstrap.shutdown();
  };

  managerClass.prototype.exists = async function exists(name) {
    ensureState(this);
    return this.sessions.has(name) || this.sessionStates.get(name) !== REMOVED;
  };

  managerClass.prototype.isRunning = function isRunning(name) {
    ensureState(this);
    return this.sessions.has(name);
  };

  managerClass.prototype.upsert = async function upsert(name, config) {
    ensureState(this);
    this.sessionConfigs.set(name, config);
    if (!this.sessionStates.has(name) || this.sessionStates.get(name) === REMOVED) {
      this.sessionStates.set(name, STOPPED);
    }
  };

  managerClass.prototype.getProxyConfig = function getProxyConfigPatched(name) {
    ensureState(this);
    const config = sessionConfig(this, name);
    if (config?.proxy) {
      return config.proxy;
    }
    return (0, helpers_proxy_1.getProxyConfig)(this.config, sessionsObject(this), name);
  };

  managerClass.prototype.start = async function start(name) {
    ensureState(this);
    if (this.sessions.has(name)) {
      throw new common_1.UnprocessableEntityException(\`Session '\${name}' is already started.\`);
    }

    const config = sessionConfig(this, name);
    this.log.info({ session: name }, 'Starting session...');
    const logger = this.log.logger.child({ session: name });
    logger.level = (0, logging_1.getPinoLogLevel)(config?.debug);
    const loggerBuilder = logger;

    const storage = await this.mediaStorageFactory.build(name, loggerBuilder.child({ name: 'Storage' }));
    await storage.init();
    const mediaManager = new MediaManager_1.MediaManager(
      storage,
      this.config.mimetypes,
      loggerBuilder.child({ name: 'MediaManager' }),
    );
    const webhook = new WebhookConductor_1.WebhookConductor(loggerBuilder);
    const proxyConfig = this.getProxyConfig(name);
    const params = {
      name,
      mediaManager,
      loggerBuilder,
      printQR: this.engineConfigService.shouldPrintQR,
      sessionStore: this.store,
      proxyConfig,
      sessionConfig: config,
      ignore: this.ignoreChatsConfig(config),
    };

    if (this.EngineClass === session_webjs_core_1.WhatsappSessionWebJSCore) {
      params.engineConfig = this.webjsEngineConfigService.getConfig();
    } else if (this.EngineClass === session_wpp_core_1.WhatsappSessionWPPCore) {
      params.engineConfig = this.wppEngineConfigService.getConfig();
    } else if (this.EngineClass === session_gows_core_1.WhatsappSessionGoWSCore) {
      params.engineConfig = this.gowsConfigService.getConfig();
    }

    await this.sessionAuthRepository.init(name);
    const session = new this.EngineClass(params);
    this.sessions.set(name, session);
    this.session = session;
    this.sessionStates.set(name, session);
    this.updateSession(name);

    const webhooks = this.getWebhooksForSession(name);
    webhook.configure(session, webhooks);

    try {
      await this.appsService.beforeSessionStart(session, this.store);
    } catch (error) {
      logger.error(\`Apps Error: \${error}\`);
      session.status = enums_dto_1.WAHASessionStatus.FAILED;
    }

    if (session.status !== enums_dto_1.WAHASessionStatus.FAILED) {
      await session.start();
      logger.info('Session has been started.');
      await this.appsService.afterSessionStart(session, this.store);
    }

    await this.appsService.afterSessionStart(session, this.store);
    return {
      name: session.name,
      status: session.status,
      config: session.sessionConfig,
    };
  };

  managerClass.prototype.updateSession = function updateSessionPatched(name) {
    ensureState(this);
    const session = this.sessions.get(name) || this.session;
    if (!session) {
      return;
    }
    for (const eventName in enums_dto_1.WAHAEvents) {
      const event = enums_dto_1.WAHAEvents[eventName];
      const stream$ = session
        .getEventObservable(event)
        .pipe((0, operators_1.map)((0, manager_abc_1.populateSessionInfo)(event, session)));
      this.events2.get(event).switch(stream$);
    }
  };

  managerClass.prototype.getSessionEvent = function getSessionEventPatched(sessionName, event) {
    ensureState(this);
    const session = this.sessions.get(sessionName);
    if (session) {
      return session
        .getEventObservable(event)
        .pipe((0, operators_1.map)((0, manager_abc_1.populateSessionInfo)(event, session)));
    }
    return this.events2.get(event);
  };

  managerClass.prototype.stop = async function stop(name, silent) {
    ensureState(this);
    if (!this.sessions.has(name)) {
      this.log.debug({ session: name }, 'Session is not running.');
      return;
    }

    this.log.info({ session: name }, 'Stopping session...');
    try {
      const session = this.getSession(name);
      await session.stop();
    } catch (error) {
      this.log.warn(\`Error while stopping session '\${name}'\`);
      if (!silent) {
        throw error;
      }
    }
    this.log.info({ session: name }, 'Session has been stopped.');
    this.sessions.delete(name);
    this.sessionStates.set(name, STOPPED);
    this.session = this.sessions.values().next().value || STOPPED;
    await (0, promiseTimeout_1.sleep)(this.SESSION_STOP_TIMEOUT);
  };

  managerClass.prototype.unpair = async function unpair(name) {
    ensureState(this);
    const session = this.sessions.get(name);
    if (!session) {
      return;
    }
    this.log.info({ session: name }, 'Unpairing the device from account...');
    await session.unpair().catch((error) => {
      this.log.warn(\`Error while unpairing from device: \${error}\`);
    });
    await (0, promiseTimeout_1.sleep)(1000);
  };

  managerClass.prototype.logout = async function logout(name) {
    await this.sessionAuthRepository.clean(name);
  };

  managerClass.prototype.delete = async function deleteSession(name) {
    ensureState(this);
    await this.appsService.removeBySession(this, name);
    this.sessions.delete(name);
    this.sessionConfigs.delete(name);
    this.sessionStates.set(name, REMOVED);
    this.session = this.sessions.values().next().value || STOPPED;
  };

  managerClass.prototype.getWebhooksForSession = function getWebhooksForSession(name) {
    const config = sessionConfig(this, name);
    let webhooks = [];
    if (config?.webhooks) {
      webhooks = webhooks.concat(config.webhooks);
    }
    const globalWebhookConfig = this.config.getWebhookConfig();
    if (globalWebhookConfig) {
      webhooks.push(globalWebhookConfig);
    }
    return webhooks;
  };

  managerClass.prototype.getSession = function getSession(name) {
    ensureState(this);
    const session = this.sessions.get(name);
    if (!session) {
      throw new common_1.NotFoundException(
        \`We didn't find a session with name '\${name}'.\\n\` +
          \`Please start it first by using POST /api/sessions/\${name}/start request\`,
      );
    }
    return session;
  };

  managerClass.prototype.getSessions = async function getSessions(all) {
    ensureState(this);
    const result = [];
    for (const [name, session] of this.sessions.entries()) {
      const me = session?.getSessionMeInfo();
      result.push({
        name,
        status: session.status,
        config: session.sessionConfig,
        me,
        presence: session.presence,
        timestamps: {
          activity: session?.getLastActivityTimestamp(),
        },
      });
    }
    if (all) {
      for (const [name, state] of this.sessionStates.entries()) {
        if (state === STOPPED && !this.sessions.has(name)) {
          result.push({
            name,
            status: enums_dto_1.WAHASessionStatus.STOPPED,
            config: sessionConfig(this, name),
            me: null,
            presence: null,
            timestamps: {
              activity: null,
            },
          });
        }
      }
    }
    return result;
  };

  managerClass.prototype.fetchEngineInfo = async function fetchEngineInfoPatched(name) {
    ensureState(this);
    const session = this.sessions.get(name);
    let engineInfo = {};
    if (session) {
      try {
        engineInfo = await (0, promiseTimeout_1.promiseTimeout)(1000, session.getEngineInfo());
      } catch (error) {
        this.log.debug({ session: session.name, error: \`\${error}\` }, 'Can not get engine info');
      }
    }
    return {
      engine: session?.engine,
      ...engineInfo,
    };
  };

  managerClass.prototype.getSessionInfo = async function getSessionInfo(name) {
    ensureState(this);
    if (this.sessionStates.get(name) === REMOVED) {
      return null;
    }
    const session = this.sessions.get(name);
    if (!session) {
      if (!this.sessionStates.has(name)) {
        return null;
      }
      return {
        name,
        status: enums_dto_1.WAHASessionStatus.STOPPED,
        config: sessionConfig(this, name),
        me: null,
        presence: null,
        timestamps: {
          activity: null,
        },
        engine: await this.fetchEngineInfo(name),
      };
    }
    const me = session.getSessionMeInfo();
    return {
      name,
      status: session.status,
      config: session.sessionConfig,
      me,
      presence: session.presence,
      timestamps: {
        activity: session.getLastActivityTimestamp(),
      },
      engine: await this.fetchEngineInfo(name),
    };
  };
})();
`;

if (!patched.includes('__wahaCoreCommunityMultiSessionPatch')) {
  patched += multiSessionPatch;
}

fs.writeFileSync(file, patched);
console.log(`WAHA Core manager patched in ${file}`);

const serviceFile = findFile(path.dirname(path.dirname(file)), 'SessionService.js');
if (!serviceFile) {
  throw new Error('No se encontro SessionService.js dentro de la imagen WAHA.');
}

let serviceSource = fs.readFileSync(serviceFile, 'utf8');
if (!serviceSource.includes('WAHA_SESSION_CREATE_REPAIR_PATCH')) {
  const servicePatched = serviceSource.replace(
    /if\s*\(await this\.manager\.exists\(name\)\)\s*\{\s*throw new .*?UnprocessableEntityException\([\s\S]*?Use PUT to update it\.`[\s\S]*?\);\s*\}/m,
    `if (await this.manager.exists(name)) {
                // WAHA_SESSION_CREATE_REPAIR_PATCH
                await this.manager.upsert(name, request.config);
                if (request.apps) {
                    await this.appsService.syncSessionApps(this.manager, name, request.apps);
                }
                if (request.start && !this.manager.isRunning(name)) {
                    await this.manager.assign(name);
                    await this.manager.start(name);
                }
                return;
            }`,
  );

  if (servicePatched === serviceSource) {
    throw new Error(`No se pudo aplicar el parche idempotente en ${serviceFile}.`);
  }

  fs.writeFileSync(serviceFile, servicePatched);
}
console.log(`WAHA Core session create repair patched in ${serviceFile}`);
EOF
  fi

  cat > docker-compose.yaml <<EOF
services:
  waha:
    image: ${WAHA_IMAGE}
    restart: always
    ports:
      - "${PORT_BINDING}"
    env_file:
      - .env
    volumes:
      - waha_sessions:/app/.sessions
      - waha_media:/app/media

volumes:
  waha_sessions:
  waha_media:
EOF
  success "docker-compose.yaml creado."

  # ── Paso 7: Pull imagen ───────────────────────────────────
  step "7" "Descargando imagen Docker" "Esto puede tardar unos minutos..."

  if [[ "$PATCH_CORE_IMAGE" == "1" ]]; then
    docker pull "${SOURCE_WAHA_IMAGE}" || error_exit "No se pudo descargar la imagen base."
    success "Imagen base descargada: ${SOURCE_WAHA_IMAGE}"
    docker build \
      -f Dockerfile.waha-core-patch \
      --build-arg "WAHA_BASE_IMAGE=${SOURCE_WAHA_IMAGE}" \
      -t "${WAHA_IMAGE}" . || error_exit "No se pudo construir la imagen parcheada."
    success "Imagen parcheada creada: ${WAHA_IMAGE}"
  else
    docker pull "${WAHA_IMAGE}" || error_exit "No se pudo descargar la imagen."
    success "Imagen descargada: ${WAHA_IMAGE}"
  fi

  # ── Paso 8: Iniciar servicio ──────────────────────────────
  step "8" "Iniciando WAHA" "Levantando contenedor..."

  docker compose up -d || error_exit "Fallo al iniciar el contenedor."

  info "Esperando que el servicio esté listo..."
  MAX_WAIT=30; WAITED=0
  until curl -s "http://localhost:${WAHA_PORT}/api/health" &>/dev/null; do
    sleep 2; WAITED=$((WAITED + 2))
    [[ $WAITED -ge $MAX_WAIT ]] && warn "Servicio tardando más de ${MAX_WAIT}s." && break
    echo -ne "  Esperando... ${WAITED}s\r"
  done
  echo ""
  success "Contenedor corriendo."

  # ── Resumen final ─────────────────────────────────────────
  # Guardar credenciales
  cat > "${INSTALL_DIR}/waha-credentials.txt" <<EOF
WAHA — Credenciales de Instalación
Generado: $(date '+%Y-%m-%d %H:%M:%S')
====================================

Dashboard URL : ${BASE_URL}/dashboard
Swagger URL   : ${BASE_URL}/docs
Health URL    : ${BASE_URL}/api/health

Dashboard User     : ${DASHBOARD_USER}
Dashboard Password : ${DASHBOARD_PASS}
API Key X-Api-Key  : ${API_KEY}
Swagger Password   : ${SWAGGER_PASS}

Directorio    : ${INSTALL_DIR}
Imagen Docker : ${WAHA_IMAGE}
EOF
  if [[ "$PATCH_CORE_IMAGE" == "1" ]]; then
    {
      echo ""
      echo "Parche Core  : onlyDefault(name) desactivado en la imagen desplegada"
      echo "Imagen base  : ${SOURCE_WAHA_IMAGE}"
      echo "Dockerfile   : ${INSTALL_DIR}/Dockerfile.waha-core-patch"
      echo "Patch script : ${INSTALL_DIR}/patch-waha-core.js"
    } >> "${INSTALL_DIR}/waha-credentials.txt"
  fi
  chmod 600 "${INSTALL_DIR}/waha-credentials.txt"

  clear
  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}║          ✅  WAHA INSTALADO CORRECTAMENTE                ║${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}📁 Directorio:${RESET}    ${INSTALL_DIR}"
  echo -e "  ${BOLD}🐳 Imagen:${RESET}        ${WAHA_IMAGE}"
  if [[ "$PATCH_CORE_IMAGE" == "1" ]]; then
    echo -e "  ${BOLD}Imagen base:${RESET}   ${SOURCE_WAHA_IMAGE}"
    echo -e "  ${BOLD}Parche:${RESET}        onlyDefault(name) desactivado"
  fi
  echo ""
  echo -e "${CYAN}${BOLD}  ┌─ URLs del Servicio ─────────────────────────────────┐${RESET}"
  echo -e "${CYAN}${BOLD}  │${RESET}"
  echo -e "${CYAN}${BOLD}  │${RESET}  🌐 Dashboard:  ${GREEN}${BOLD}${BASE_URL}/dashboard${RESET}"
  echo -e "${CYAN}${BOLD}  │${RESET}  📖 Swagger UI: ${GREEN}${BOLD}${BASE_URL}/docs${RESET}"
  echo -e "${CYAN}${BOLD}  │${RESET}  ❤  Health:     ${GREEN}${BOLD}${BASE_URL}/api/health${RESET}"
  echo -e "${CYAN}${BOLD}  │${RESET}"
  echo -e "${CYAN}${BOLD}  └─────────────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}  ┌─ Credenciales ──────────────────────────────────────┐${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}  👤 Dashboard user: ${BOLD}${DASHBOARD_USER}${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}  🔑 Dashboard pass: ${BOLD}${DASHBOARD_PASS}${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}  🗝  API X-Api-Key: ${BOLD}${API_KEY}${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}  📄 Swagger pass:   ${BOLD}${SWAGGER_PASS}${RESET}"
  echo -e "${YELLOW}${BOLD}  │${RESET}"
  echo -e "${YELLOW}${BOLD}  └─────────────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  ${CYAN}💾 Guardado en: ${BOLD}${INSTALL_DIR}/waha-credentials.txt${RESET}"
  echo ""
  echo -e "${BOLD}  Comandos útiles:${RESET}"
  echo -e "  cd ${INSTALL_DIR}"
  echo -e "  docker compose logs -f"
  echo -e "  docker compose restart"
  echo -e "  docker compose down"
  if [[ "$PATCH_CORE_IMAGE" == "1" ]]; then
    echo -e "  docker pull ${SOURCE_WAHA_IMAGE} && docker build -f Dockerfile.waha-core-patch --build-arg WAHA_BASE_IMAGE=${SOURCE_WAHA_IMAGE} -t ${WAHA_IMAGE} . && docker compose up -d"
  else
    echo -e "  docker compose pull && docker compose up -d"
  fi
  echo ""

  prompt_continue
  main_menu
}

# ── Entrada principal ─────────────────────────────────────────
main_menu
