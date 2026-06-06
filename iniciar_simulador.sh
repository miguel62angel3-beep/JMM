#!/bin/bash
set -euo pipefail
#
# iniciar_simulador.sh — Arranque robusto: MediaMTX + Simulador Python
# Características:
#   • Lock file previene duplicados
#   • Health check vía /proc/net/tcp (sin netcat)
#   • Captura de PID para shutdown controlado
#   • Manejo de señales (SIGINT, SIGTERM)
#   • Auto-restart con backoff exponencial
#   • Log rotación automática
#

readonly PROYECTO="${HOME}/simulador_plataforma"
readonly LOG_DIR="${PROYECTO}/logs"
readonly LOCK_FILE="${PROYECTO}/.simulador.lock"
readonly PID_FILE="${PROYECTO}/.simulador.pids"
readonly MTX_LOG="${LOG_DIR}/mediamtx.log"
readonly SIM_LOG="${LOG_DIR}/simulador.log"
readonly MTX_CONFIG="${PROYECTO}/mediamtx.yml"
readonly MTX_BIN="${PROYECTO}/mediamtx"
readonly SIM_BIN="${PROYECTO}/simulador_camaras.py"

# Configuración
readonly MTX_PORT=8554
readonly MTX_MAX_WAIT=30          # segundos esperando MediaMTX
readonly START_RETRIES=3          # intentos de arranque
readonly RESTART_INTERVAL=60      # segundos entre reintentos de auto-restart

# ── Utilidades ─────────────────────────────────────
log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg"
    mkdir -p "$LOG_DIR"
    echo "$msg" >> "${LOG_DIR}/iniciar.log" 2>/dev/null || true
}

fail() { log "FATAL: $*"; cleanup; exit 1; }

# Health check nativo (sin netcat): revisa /proc/net/tcp
tcp_port_open() {
    local port_hex
    port_hex=$(printf '%04X' "$1")
    grep -q ":${port_hex} 01 " /proc/net/tcp 2>/dev/null
}

# ── Lock file ──────────────────────────────────────
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null) || true
        if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
            log "⚠ Ya hay una instancia corriendo (PID $old_pid)"
            log "  Usa: bash $0 stop    — para detener"
            log "  O:   rm $LOCK_FILE  — si quedó huérfano"
            exit 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ── Gestión de PIDs ────────────────────────────────
record_pid() {
    local name="$1" pid="$2"
    echo "${name}=${pid}" >> "$PID_FILE"
}

read_pid() {
    local name="$1"
    grep "^${name}=" "$PID_FILE" 2>/dev/null | cut -d= -f2 | tail -1
}

clear_pids() {
    rm -f "$PID_FILE"
}

# ── Shutdown graceful ──────────────────────────────
cleanup() {
    log "→ Deteniendo servicios..."
    local pid

    # Detener simulador primero (es cliente de MediaMTX)
    pid=$(read_pid "simulador") || true
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        log "  Enviando SIGTERM al simulador (PID $pid)..."
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi

    # Detener MediaMTX
    pid=$(read_pid "mediamtx") || true
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        log "  Enviando SIGTERM a MediaMTX (PID $pid)..."
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi

    clear_pids
    release_lock
    log "✓ Servicios detenidos"
}

trap cleanup EXIT SIGINT SIGTERM

# ── Comando: stop ──────────────────────────────────
if [ "${1:-}" = "stop" ]; then
    log "Solicitando parada..."
    if [ -f "$LOCK_FILE" ]; then
        local master_pid
        master_pid=$(cat "$LOCK_FILE")
        kill -TERM "$master_pid" 2>/dev/null || true
        log "✓ Señal enviada al proceso $master_pid"
    else
        log "⚠ No hay lock file. Limpiando PIDs residuales..."
        cleanup
    fi
    exit 0
fi

# ── Validaciones ───────────────────────────────────
[ -d "$PROYECTO" ] || fail "No existe $PROYECTO. Ejecuta setup.sh primero"
[ -x "$MTX_BIN" ]  || fail "MediaMTX no encontrado en $MTX_BIN"
[ -f "$SIM_BIN" ]  || fail "Simulador no encontrado en $SIM_BIN"
[ -f "$MTX_CONFIG" ] || fail "Config no encontrada en $MTX_CONFIG"

mkdir -p "$LOG_DIR"

# Rotar logs si son muy grandes (>5MB)
for f in "$MTX_LOG" "$SIM_LOG"; do
    if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -gt 5242880 ]; then
        mv "$f" "${f}.old"
    fi
done

acquire_lock

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   Iniciando Simulador de Cámaras IP                ║"
echo "╚════════════════════════════════════════════════════╝"

# ═══════════════════════════════════════════════════
# 1. MediaMTX
# ═══════════════════════════════════════════════════
start_mediamtx() {
    local attempt=1
    while [ "$attempt" -le "$START_RETRIES" ]; do
        log "[1] Arrancando MediaMTX (intento $attempt/$START_RETRIES)..."

        # Verificar si ya corre
        local existing_pid
        existing_pid=$(read_pid "mediamtx") || true
        if [ -n "${existing_pid:-}" ] && kill -0 "$existing_pid" 2>/dev/null; then
            log "    ✓ MediaMTX ya activo (PID $existing_pid)"
            return 0
        fi

        # Arrancar
        "$MTX_BIN" "$MTX_CONFIG" >> "$MTX_LOG" 2>&1 &
        local pid=$!
        record_pid "mediamtx" "$pid"

        # Health check con timeout
        local waited=0
        while ! tcp_port_open "$MTX_PORT"; do
            sleep 1
            waited=$((waited + 1))
            if [ "$waited" -ge "$MTX_MAX_WAIT" ]; then
                log "    ✗ Timeout esperando puerto $MTX_PORT"
                kill -TERM "$pid" 2>/dev/null || true
                break
            fi
            # Verificar que el proceso no murió prematuramente
            if ! kill -0 "$pid" 2>/dev/null; then
                log "    ✗ MediaMTX murió antes de abrir el puerto"
                break
            fi
        done

        if tcp_port_open "$MTX_PORT"; then
            log "    ✓ MediaMTX listo en ${waited}s (PID $pid)"
            return 0
        fi

        attempt=$((attempt + 1))
        [ "$attempt" -le "$START_RETRIES" ] && sleep 5
    done

    return 1
}

start_mediamtx || fail "MediaMTX no pudo iniciar después de $START_RETRIES intentos. Revisa $MTX_LOG"

# ═══════════════════════════════════════════════════
# 2. Simulador Python
# ═══════════════════════════════════════════════════
start_simulador() {
    log "[2] Arrancando simulador de cámaras..."

    local existing_pid
    existing_pid=$(read_pid "simulador") || true
    if [ -n "${existing_pid:-}" ] && kill -0 "$existing_pid" 2>/dev/null; then
        log "    ✓ Simulador ya activo (PID $existing_pid)"
        return 0
    fi

    # Detectar interprete Python
    local PYTHON="python3"
    command -v python3 &>/dev/null || PYTHON="python"

    cd "$PROYECTO" || fail "No se pudo entrar a $PROYECTO"
    $PYTHON "$SIM_BIN" >> "$SIM_LOG" 2>&1 &
    local pid=$!
    record_pid "simulador" "$pid"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        log "    ✓ Simulador activo (PID $pid)"
        return 0
    else
        log "    ✗ El simulador no arrancó. Revisa $SIM_LOG"
        return 1
    fi
}

start_simulador || fail "El simulador no pudo iniciar. Revisa $SIM_LOG"

# ═══════════════════════════════════════════════════
# 3. Resumen
# ═══════════════════════════════════════════════════
IP=$(
    ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1 || \
    ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1 || \
    echo "<desconocida>"
)
IP="${IP:-<desconocida>}"

log ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✓ Servicios activos                               ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║  RTSP:   rtsp://${IP}:${MTX_PORT}/camara_{1..N}"
echo "║  HLS:    http://${IP}:8888/camara_N/"
echo "║  WebRTC: http://${IP}:8889/camara_N/"
echo "╠════════════════════════════════════════════════════╣"
echo "║  Monitoreo:                                        ║"
echo "║    Logs:    tail -f ${LOG_DIR}/*.log"
echo "║    Parar:   bash ${PROYECTO}/iniciar_simulador.sh stop"
echo "╚════════════════════════════════════════════════════╝"

# ═══════════════════════════════════════════════════
# 4. Watchdog (auto-restart si algo muere)
# ═══════════════════════════════════════════════════
log "[WATCHDOG] Monitoreando procesos cada ${RESTART_INTERVAL}s..."
while true; do
    sleep "$RESTART_INTERVAL"

    # Revisar MediaMTX
    local mtx_pid
    mtx_pid=$(read_pid "mediamtx") || true
    if [ -z "${mtx_pid:-}" ] || ! kill -0 "$mtx_pid" 2>/dev/null || ! tcp_port_open "$MTX_PORT"; then
        log "[WATCHDOG] MediaMTX caído. Reintentando..."
        start_mediamtx || log "[WATCHDOG] No se pudo revivir MediaMTX"
    fi

    # Revisar simulador
    local sim_pid
    sim_pid=$(read_pid "simulador") || true
    if [ -z "${sim_pid:-}" ] || ! kill -0 "$sim_pid" 2>/dev/null; then
        log "[WATCHDOG] Simulador caído. Reintentando..."
        start_simulador || log "[WATCHDOG] No se pudo revivir el simulador"
    fi
done
