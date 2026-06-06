#!/bin/bash
set -euo pipefail
#
# adb_deploy.sh — Control total del simulador RTSP desde PC via ADB
# Requisitos: adb instalado, dispositivo conectado (adb devices)
#
# USO:
#   ./adb_deploy.sh install     → Instala Termux + despliega todo
#   ./adb_deploy.sh start       → Inicia el simulador en el dispositivo
#   ./adb_deploy.sh stop        → Detiene el simulador
#   ./adb_deploy.sh status      → Muestra estado de los servicios
#   ./adb_deploy.sh logs        → Muestra logs en tiempo real
#   ./adb_deploy.sh forward     → Abre túnel RTSP/HLS a localhost
#   ./adb_deploy.sh shell       → Abre shell interactiva de Termux
#   ./adb_deploy.sh uninstall   → Limpia todo del dispositivo
#

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TERMUX_VERSION="v0.119.0-beta.2"
readonly TERMUX_APK="termux-app_${TERMUX_VERSION}+apt-android-7-github-debug_arm64-v8a.apk"
readonly TERMUX_URL="https://github.com/termux/termux-app/releases/download/${TERMUX_VERSION}/${TERMUX_APK}"

# Rutas dentro del dispositivo (entorno Termux)
readonly TERMUX_PREFIX="/data/data/com.termux/files"
readonly TERMUX_HOME="${TERMUX_PREFIX}/home"
readonly TERMUX_BIN="${TERMUX_PREFIX}/usr/bin"
readonly PROYECTO="${TERMUX_HOME}/simulador_plataforma"
readonly SDCARD_PROJ="/sdcard/simulador_plataforma"

# Colores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${C}[ADB]${NC} $*"; }
ok()   { echo -e "${G}[OK]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*"; }
err()  { echo -e "${R}[ERR]${NC} $*"; }

# ── Verificaciones ─────────────────────────────────
check_adb() {
    command -v adb &>/dev/null || { err "adb no encontrado. Instala Android Platform Tools."; exit 1; }
    local devices
    devices=$(adb devices | grep -v "List" | grep "device$" | wc -l)
    [ "$devices" -eq 1 ] || {
        err "Se requiere exactamente 1 dispositivo conectado."
        adb devices
        exit 1
    }
    ok "Dispositivo detectado"
}

check_termux_installed() {
    adb shell pm list packages | grep -q "com.termux" || return 1
}

# ── Instalar Termux ────────────────────────────────
cmd_install_termux() {
    check_adb
    log "Verificando Termux..."

    if check_termux_installed; then
        ok "Termux ya está instalado"
    else
        log "Descargando Termux ${TERMUX_VERSION}..."
        [ -f "/tmp/${TERMUX_APK}" ] || curl -fL -o "/tmp/${TERMUX_APK}" "$TERMUX_URL"
        log "Instalando APK..."
        adb install -r -d "/tmp/${TERMUX_APK}" || {
            err "Fallo instalación. Prueba: adb install -r -d /tmp/${TERMUX_APK}"
            exit 1
        }
        ok "Termux instalado"
    fi

    # Solicitar permiso de almacenamiento
    log "Solicitando permisos..."
    adb shell am start -n com.termux/.app.TermuxActivity &>/dev/null || true
    sleep 1
    adb shell pm grant com.termux android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null || true
}

# ── Push de archivos ───────────────────────────────
cmd_push_files() {
    check_adb
    log "Preparando archivos en el dispositivo..."

    # Crear estructura en /sdcard (accesible desde Termux y PC)
    adb shell "mkdir -p ${SDCARD_PROJ}/videos"

    # Push de archivos locales si existen en el mismo directorio
    if [ -f "${SCRIPT_DIR}/simulador_camaras_android.py" ]; then
        adb push "${SCRIPT_DIR}/simulador_camaras_android.py" "${SDCARD_PROJ}/"
    else
        warn "No se encontró simulador_camaras_android.py en ${SCRIPT_DIR}"
        warn "Colócalo manualmente en ${SDCARD_PROJ}/ del dispositivo"
    fi

    if [ -f "${SCRIPT_DIR}/mediamtx" ] || [ -f "${SCRIPT_DIR}/mediamtx_arm64" ]; then
        local src="${SCRIPT_DIR}/mediamtx"
        [ -f "${SCRIPT_DIR}/mediamtx_arm64" ] && src="${SCRIPT_DIR}/mediamtx_arm64"
        adb push "$src" "${SDCARD_PROJ}/mediamtx"
    fi

    # Push de los scripts mejorados
    if [ -f "${SCRIPT_DIR}/setup.sh" ]; then
        adb push "${SCRIPT_DIR}/setup.sh" "${SDCARD_PROJ}/"
    fi
    if [ -f "${SCRIPT_DIR}/iniciar_simulador.sh" ]; then
        adb push "${SCRIPT_DIR}/iniciar_simulador.sh" "${SDCARD_PROJ}/"
    fi

    ok "Archivos transferidos a ${SDCARD_PROJ}"
}

# ── Ejecutar setup dentro de Termux ────────────────
cmd_setup() {
    check_adb
    log "Ejecutando setup en Termux (esto puede tardar)..."

    # Ejecutar setup.sh dentro del entorno Termux
    adb shell "${TERMUX_BIN}/bash ${SDCARD_PROJ}/setup.sh" || {
        err "El setup falló. Conecta el dispositivo a WiFi y reintenta."
        exit 1
    }

    ok "Setup completado en el dispositivo"
}

# ── Iniciar simulador ──────────────────────────────
cmd_start() {
    check_adb
    log "Iniciando simulador RTSP..."

    # Usar nohup para que sobreviva al cierre de la sesión ADB
    adb shell "cd ${PROYECTO} && nohup ${TERMUX_BIN}/bash ${PROYECTO}/iniciar_simulador.sh > /dev/null 2>&1 &"

    sleep 3
    local mtx_pid sim_pid
    mtx_pid=$(adb shell "cat ${PROYECTO}/.simulador.pids 2>/dev/null | grep mediamtx | cut -d= -f2" 2>/dev/null | tr -d '\r')
    sim_pid=$(adb shell "cat ${PROYECTO}/.simulador.pids 2>/dev/null | grep simulador | cut -d= -f2" 2>/dev/null | tr -d '\r')

    [ -n "${mtx_pid:-}" ] && ok "MediaMTX PID: $mtx_pid"
    [ -n "${sim_pid:-}" ] && ok "Simulador PID: $sim_pid"

    log ""
    log "Para ver logs:  ./adb_deploy.sh logs"
    log "Para detener:   ./adb_deploy.sh stop"
}

# ── Detener simulador ──────────────────────────────
cmd_stop() {
    check_adb
    log "Deteniendo servicios..."
    adb shell "${TERMUX_BIN}/bash ${PROYECTO}/iniciar_simulador.sh stop 2>/dev/null" || {
        # Fallback: matar procesos directamente
        adb shell "pkill -f mediamtx 2>/dev/null; pkill -f simulador_camaras 2>/dev/null; rm -f ${PROYECTO}/.simulador.lock ${PROYECTO}/.simulador.pids" || true
    }
    ok "Servicios detenidos"
}

# ── Estado ─────────────────────────────────────────
cmd_status() {
    check_adb
    log "Estado de los servicios:"
    echo ""

    local mtx_running=false sim_running=false ip="<desconocida>"

    if adb shell "pgrep -x mediamtx" &>/dev/null; then
        mtx_running=true
        local pid
        pid=$(adb shell "pgrep -x mediamtx" 2>/dev/null | tr -d '\r')
        echo -e "  MediaMTX: ${G}ACTIVO${NC} (PID $pid)"
    else
        echo -e "  MediaMTX: ${R}INACTIVO${NC}"
    fi

    if adb shell "pgrep -f simulador_camaras" &>/dev/null; then
        sim_running=true
        local pid
        pid=$(adb shell "pgrep -f simulador_camaras" 2>/dev/null | tr -d '\r')
        echo -e "  Simulador: ${G}ACTIVO${NC} (PID $pid)"
    else
        echo -e "  Simulador: ${R}INACTIVO${NC}"
    fi

    ip=$(adb shell "ip route | grep src | awk '{print \\$9}' | head -1" 2>/dev/null | tr -d '\r')
    [ -z "$ip" ] && ip=$(adb shell "ifconfig | grep 'inet ' | grep -v 127 | awk '{print \$2}' | head -1" 2>/dev/null | tr -d '\r')

    echo ""
    if $mtx_running; then
        echo "  URLs del dispositivo:"
        echo "    RTSP:   rtsp://${ip}:8554/camara_N"
        echo "    HLS:    http://${ip}:8888/camara_N"
        echo ""
        echo "  (Si hiciste forward: rtsp://localhost:8554/camara_N)"
    fi
}

# ── Logs ───────────────────────────────────────────
cmd_logs() {
    check_adb
    log "Mostrando logs (Ctrl+C para salir)..."
    echo ""

    # Mostrar últimas 50 líneas de cada log
    echo "=== MediaMTX ==="
    adb shell "tail -n 50 ${PROYECTO}/logs/mediamtx.log 2>/dev/null || echo 'Sin log'"
    echo ""
    echo "=== Simulador ==="
    adb shell "tail -n 50 ${PROYECTO}/logs/simulador.log 2>/dev/null || echo 'Sin log'"
}

# ── Port Forwarding ────────────────────────────────
cmd_forward() {
    check_adb
    log "Configurando port forwarding..."

    # Eliminar forwards previos para evitar duplicados
    adb forward --remove tcp:8554 2>/dev/null || true
    adb forward --remove tcp:8888 2>/dev/null || true
    adb forward --remove tcp:8889 2>/dev/null || true

    adb forward tcp:8554 tcp:8554
    adb forward tcp:8888 tcp:8888
    adb forward tcp:8889 tcp:8889

    ok "Túneles activos:"
    echo "  RTSP:   rtsp://localhost:8554/camara_N"
    echo "  HLS:    http://localhost:8888/camara_N"
    echo "  WebRTC: http://localhost:8889/camara_N"
    echo ""
    echo "  (Solo funcionan mientras el dispositivo está conectado por USB)"
}

# ── Shell interactivo de Termux ────────────────────
cmd_shell() {
    check_adb
    log "Abriendo shell de Termux..."
    adb shell "${TERMUX_BIN}/bash -l"
}

# ── Uninstall ──────────────────────────────────────
cmd_uninstall() {
    check_adb
    warn "Esto eliminará TODO el simulador del dispositivo."
    read -r -p "¿Continuar? [s/N]: " confirm
    [[ "$confirm" =~ ^[Ss]$ ]] || { log "Cancelado"; exit 0; }

    cmd_stop 2>/dev/null || true
    adb shell "rm -rf ${PROYECTO} ${SDCARD_PROJ}" || true
    adb shell "rm -f ${TERMUX_HOME}/mediamtx.yml" || true
    ok "Simulador eliminado"
}

# ── Instalación completa ───────────────────────────
cmd_install() {
    log "=== INSTALACIÓN COMPLETA ==="
    cmd_install_termux
    cmd_push_files
    cmd_setup
    echo ""
    ok "=== INSTALACIÓN FINALIZADA ==="
    log ""
    log "Próximos pasos:"
    log "  1. Coloca tus videos .mp4 en:  ${SDCARD_PROJ}/videos/"
    log "  2. Inicia el simulador:         ./adb_deploy.sh start"
    log "  3. Abre el túnel:               ./adb_deploy.sh forward"
    log "  4. Ver logs:                    ./adb_deploy.sh logs"
}

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════
case "${1:-}" in
    install)    cmd_install ;;
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    status)     cmd_status ;;
    logs)       cmd_logs ;;
    forward)    cmd_forward ;;
    shell)      cmd_shell ;;
    uninstall)  cmd_uninstall ;;
    setup)      cmd_setup ;;
    push)       cmd_push_files ;;
    *)
        echo "Uso: $0 {install|start|stop|status|logs|forward|shell|uninstall}"
        echo ""
        echo "Comandos:"
        echo "  install    → Instala Termux + despliega todo de cero"
        echo "  start      → Inicia el simulador RTSP en el dispositivo"
        echo "  stop       → Detiene el simulador"
        echo "  status     → Muestra estado de MediaMTX y el simulador"
        echo "  logs       → Muestra últimas líneas de logs"
        echo "  forward    → Crea túneles ADB para acceso local (RTSP/HLS)"
        echo "  shell      → Abre shell interactiva de Termux"
        echo "  uninstall  → Elimina todo el simulador del dispositivo"
        exit 1
        ;;
esac
