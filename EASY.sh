#!/bin/bash
# EASY.sh
# Instalación completa desde GitHub usando WGET. Ejecutar una sola vez.

set -e
GITHUB_URL="https://githubusercontent.com"
PROYECTO=~/simulador_plataforma

echo "=== Setup Simulador de Cámaras Android (Vía Wget) ==="

# 1. Permisos de almacenamiento (Acepta automáticamente el aviso interactivo)
echo "" | termux-setup-storage 2>/dev/null || true
sleep 2

# 2. Paquetes del sistema
pkg update -y
pkg install -y python ffmpeg netcat-openbsd wget

# 3. Dependencias Python
pip install --quiet flask flask-cors requests

# 4. Estructura de carpetas local
mkdir -p "$PROYECTO"
mkdir -p ~/storage/shared/simulador_plataforma/videos

# 5. Descargar archivos del simulador directamente de GitHub usando Wget
echo "Descargando archivos desde GitHub..."
wget -q --no-check-certificate "$GITHUB_URL/simulador_camaras_android.py" -O "$PROYECTO/simulador_camaras.py"
wget -q --no-check-certificate "$GITHUB_URL/web_server_android.py"        -O "$PROYECTO/web_server_simulador.py"
wget -q --no-check-certificate "$GITHUB_URL/dashboard_simulador.html"     -O "$PROYECTO/dashboard_simulador.html"
wget -q --no-check-certificate "$GITHUB_URL/iniciar_simulador.sh"         -O "$PROYECTO/iniciar_simulador.sh"
wget -q --no-check-certificate "$GITHUB_URL/detener_simulador.sh"         -O "$PROYECTO/detener_simulador.sh"
chmod +x "$PROYECTO/iniciar_simulador.sh" "$PROYECTO/detener_simulador.sh"

# 6. Descargar Binario MediaMTX desde GitHub
wget -q --no-check-certificate "$GITHUB_URL/mediamtx_arm64" -O "$PROYECTO/mediamtx"
chmod +x "$PROYECTO/mediamtx"

# 7. Enlace simbólico de videos apuntando a la memoria interna compartida
ln -sf ~/storage/shared/simulador_plataforma/videos "$PROYECTO/videos"

# 8. Configuración de MediaMTX
cat > ~/mediamtx.yml << 'EOF'
rtspAddress: :8554
hlsAddress: :8888
hlsAlwaysRemux: yes
webrtcAddress: :8889
api: yes
apiAddress: :9997

paths:
  all: {}
EOF

# 9. Widgets Termux:Widget
mkdir -p ~/.shortcuts/tasks
cp "$PROYECTO/iniciar_simulador.sh" ~/.shortcuts/tasks/Iniciar_Simulador
cp "$PROYECTO/detener_simulador.sh" ~/.shortcuts/tasks/Detener_Simulador
chmod +x ~/.shortcuts/tasks/Iniciar_Simulador ~/.shortcuts/tasks/Detener_Simulador

# 10. Habilitar apps externas (Termux:Widget) sin colgar la app
mkdir -p ~/.termux
touch ~/.termux/termux.properties
sed -i '/allow-external-apps/d' ~/.termux/termux.properties 2>/dev/null || true
echo "allow-external-apps = true" >> ~/.termux/termux.properties

echo ""
echo "=== ¡Instalación Exitosa! ==="
echo "Pon tus videos .mp4 en la carpeta de tu celular: simulador_plataforma/videos/"
echo "El entorno se reiniciará en 3 segundos para aplicar los cambios..."
sleep 3

logout
