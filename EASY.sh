cat << 'EOF' > setup_comodidad_total.sh
#!/bin/bash

# =====================================================================
#  PROYECTO COMODIDAD: DESPLIEGUE MASIVO 100% DESATENDIDO
# =====================================================================

# CONFIGURACIÓN INICIAL (Modifica aquí la clave para los 100+ equipos)
CONTRASENA_POR_DEFECTO="Dispositivo2026!"

echo "========================================================="
echo "       INICIANDO DESPLIEGUE AUTOMATIZADO EN MASA         "
echo "========================================================="

# 1. ACTUALIZACIÓN E INSTALACIÓN CORE (Forzando respuestas afirmativas)
echo "[+] Actualizando repositorios e instalando dependencias..."
export DEBIAN_FRONTEND=noninteractive
pkg update -y -o Dpkg::Options::="--force-confold"
pkg upgrade -y -o Dpkg::Options::="--force-confold"
pkg install -y openssh git curl wget tmux neovim proot-distro termux-tools

# 2. CONFIGURACIÓN DE SEGURIDAD AUTOMÁTICA (Cero Prompts)
echo "[+] Configurando credenciales de acceso..."
echo -e "$CONTRASENA_POR_DEFECTO\n$CONTRASENA_POR_DEFECTO" | passwd > /dev/null 2>&1

# 3. AUTOMATIZACIÓN DE PERSISTENCIA (SSHD AL INICIO)
echo "[+] Configurando persistencia del servidor..."
sshd 

mkdir -p ~/.bashrc_fragments
if [ ! -f ~/.bashrc ]; then touch ~/.bashrc; fi

if ! grep -q "sshd" ~/.bashrc; then
    echo "sshd" >> ~/.bashrc
fi

# 4. ENLACE DE ALMACENAMIENTO (Solución desatendida para Android)
# NOTA: En Android moderno, termux-setup-storage SIEMPRE lanzará un pop-up visual del sistema.
# Para evitar que el script se pause esperando, lo enviamos al fondo.
echo "[+] Solicitando permisos de almacenamiento en segundo plano..."
termux-setup-storage &

# 5. RECOLECCIÓN AUTOMÁTICA DE PARÁMETROS DE RED
echo "[+] Extrayendo parámetros de red..."
USUARIO=$(whoami)
IP_LOCAL=$(ifconfig 2>/dev/null | grep -E "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -n 1)

if [ -z "$IP_LOCAL" ]; then
    IP_LOCAL=$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -n 1)
fi

echo "========================================================="
echo "        [✔] ¡DISPOSITIVO CONFIGURADO CON ÉXITO!          "
echo "========================================================="
echo "Acceso remoto listo para este terminal:"
echo "  ssh ${USUARIO}@${IP_LOCAL:-DETECTANDO_IP} -p 8022"
echo "========================================================="
EOF
chmod +x setup_comodidad_total.sh && ./setup_comodidad_total.sh
