#!/bin/bash
set -euo pipefail
#
# setup.sh — Instalación robusta del simulador RTSP en Termux
# Uso: bash setup.sh
# Ejecutar DESDE Termux, no desde adb shell directamente.
#

readonly PROYECTO="${HOME}/simulador_plataforma"
readonly SDCARD="/sdcard/simulador_plataforma"
readonly MTX_VERSION="1.9.3"
readonly MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VERSION}/mediamtx_v${MTX_VERSION}_linux_arm64v8.tar.gz"
readonly LOG="${PROYECTO}/setup.log"

# ── Utilidades ─────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
fail() { log "ERROR: $*"; exit 1; }

check_termux() {
    [[ "${PREFIX:-}" == *"com.termux"* ]] || fail "Este script debe ejecutarse dentro de Termux"
}

# ── 0. Verificar entorno ───────────────────────────
check_termux
mkdir -p "$PROYECTO"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  Setup Simulador RTSP — Android/Termux             ║"
echo "╚════════════════════════════════════════════════════╝"
log "Iniciando instalación..."

# ── 1. Almacenamiento (con verificación) ───────────
log "[1/6] Solicitando permiso de almacenamiento..."
if [ ! -d "$SDCARD" ]; then
    termux-setup-storage
    # Espera activa con timeout de 30s (mejor que sleep fijo)
    for i in {1..30}; do
        [ -d "$SDCARD" ] && break
        sleep 1
    done
    [ -d "$SDCARD" ] || fail "No se concedió permiso de almacenamiento en 30s"
fi
log "      ✓ Almacenamiento listo"

# ── 2. Paquetes (idempotente) ──────────────────────
log "[2/6] Verificando paquetes..."
need_update=false
for pkg in python ffmpeg curl; do
    if ! command -v "$pkg" &>/dev/null; then
        need_update=true
        break
    fi
done

if $need_update; then
    pkg update -y
    pkg install -y python ffmpeg curl || fail "No se pudieron instalar paquetes"
fi
log "      ✓ Paquetes listos"

# ── 3. Copiar archivos del proyecto ────────────────
log "[3/6] Desplegando archivos..."
[ -f "$SDCARD/simulador_camaras_android.py" ] || fail "No existe $SDCARD/simulador_camaras_android.py"

cp "$SDCARD/simulador_camaras_android.py" "$PROYECTO/simulador_camaras.py"
cp "$SDCARD/iniciar_simulador.sh" "$PROYECTO/" 2>/dev/null || true
chmod +x "$PROYECTO"/*.sh 2>/dev/null || true
log "      ✓ Archivos copiados"

# ── 4. MediaMTX ────────────────────────────────────
log "[4/6] Instalando MediaMTX v${MTX_VERSION}..."
if [ -f "$PROYECTO/mediamtx" ] && "$PROYECTO/mediamtx" --version &>/dev/null; then
    log "      ✓ MediaMTX ya instalado y funcional"
else
    # Prioridad: binario local > descarga
    if [ -f "$SDCARD/mediamtx" ] || [ -f "$SDCARD/mediamtx_arm64" ]; then
        src="$SDCARD/mediamtx"
        [ -f "$SDCARD/mediamtx_arm64" ] && src="$SDCARD/mediamtx_arm64"
        cp "$src" "$PROYECTO/mediamtx"
        log "      ✓ Binario local copiado"
    else
        log "      → Descargando desde GitHub..."
        curl -fL --progress-bar -o "$PROYECTO/mtx.tar.gz" "$MTX_URL" || fail "Descarga fallida"
        tar -xzf "$PROYECTO/mtx.tar.gz" -C "$PROYECTO" mediamtx
        rm -f "$PROYECTO/mtx.tar.gz"
        log "      ✓ Descarga completada"
    fi
    chmod +x "$PROYECTO/mediamtx"
    "$PROYECTO/mediamtx" --version &>/dev/null || fail "El binario MediaMTX no es ejecutable"
fi

# ── 5. Videos (symlink robusto) ────────────────────
log "[5/6] Configurando carpeta de videos..."
mkdir -p "$SDCARD/videos"
rm -f "$PROYECTO/videos"
ln -sf "$SDCARD/videos" "$PROYECTO/videos"
log "      ✓ Enlace creado: $PROYECTO/videos → $SDCARD/videos"

# ── 6. Configuración MediaMTX ──────────────────────
log "[6/6] Escribiendo configuración..."
cat > "$PROYECTO/mediamtx.yml" << 'EOF'
logLevel: warn
logDestinations: [file]
logFile: /sdcard/simulador_plataforma/mediamtx.log

rtsp: true
rtspAddress: :8554

hls: true
hlsAddress: :8888
hlsAlwaysRemux: yes
hlsVariant: lowLatency

webrtc: true
webrtcAddress: :8889

api: true
apiAddress: :9997

# Autenticación: SOLO permite publicar desde localhost
# Esto bloquea que cualquier dispositivo en la red inyecte streams
authMethod: internal
authInternalUsers:
  - user: publish
    pass: ""
    ips: ["127.0.0.1", "::1"]
    permissions:
      - action: publish
  - user: any
    pass:
    permissions:
      - action: read

paths:
  all: {}
  camara_1:
    source: publisher
  camara_2:
    source: publisher
  camara_3:
    source: publisher
  camara_4:
    source: publisher
EOF

# ── 7. Widget de inicio rápido (opcional) ──────────
if [ -d "${HOME}/.shortcuts" ]; then
    mkdir -p "${HOME}/.shortcuts/tasks"
    cp "$PROYECTO/iniciar_simulador.sh" "${HOME}/.shortcuts/tasks/Iniciar_Simulador" 2>/dev/null || true
    chmod +x "${HOME}/.shortcuts/tasks/Iniciar_Simulador" 2>/dev/null || true
    log "      ✓ Widget de Termux configurado"
fi

# ── Resumen ────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✓ Instalación completada                          ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║  Directorio:  ${PROYECTO}"
echo "║  Videos:      ${SDCARD}/videos/"
echo "║  Log setup:   ${LOG}"
echo "╠════════════════════════════════════════════════════╣"
echo "║  Para iniciar:                                     ║"
echo "║    bash ${PROYECTO}/iniciar_simulador.sh"
echo "╚════════════════════════════════════════════════════╝"
