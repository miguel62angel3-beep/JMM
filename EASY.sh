#!/bin/bash

# Asegurar que el script termine si ocurre un error inesperado (excepto los controlados)
set -e

echo "=================================================="
echo "   Asistente de Instalación Robusta de SSH"
echo "=================================================="

# 1. Solicitar intervención y confirmación del usuario
echo -n "¿Deseas proceder con la instalación y configuración de SSH? (s/n): "
read -r respuesta

if [[ ! "$respuesta" =~ ^[sS]$ && ! "$respuesta" =~ ^[yY]$ ]]; then
    echo "Operación cancelada por el usuario."
    exit 0
fi

# 2. Verificar que se ejecute con privilegios de administrador (sudo)
if [ "$EUID" -ne 0 ]; then
    echo "Error: Este script requiere privilegios de administrador."
    echo "Por favor, ejecútalo usando: sudo ./instalar_ssh.sh"
    exit 1
fi

# 3. Detectar el gestor de paquetes del sistema operativo
echo "Detectando sistema operativo..."
if [ -f /etc/debian_version ]; then
    PAQUETE="openssh-server"
    ACTUALIZAR_CMD="apt-get update -y"
    INSTALAR_CMD="apt-get install -y $PAQUETE"
    SERVICIO="ssh"
elif [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
    PAQUETE="openssh-server"
    ACTUALIZAR_CMD="dnf check-update -y || true" # dnf devuelve 100 si hay actualizaciones, evitamos que rompa el script
    INSTALAR_CMD="dnf install -y $PAQUETE"
    SERVICIO="sshd"
else
    echo "Error: Sistema operativo no compatible o no detectado."
    exit 1
fi

# 4. Actualizar las listas de paquetes de forma segura
echo "Actualizando los repositorios del sistema..."
if eval "$ACTUALIZAR_CMD"; then
    echo "Repositorios actualizados correctamente."
else
    echo "Advertencia: No se pudieron actualizar los repositorios, intentando instalar de todos modos..."
fi

# 5. Instalación robusta del paquete SSH
echo "Instalando $PAQUETE..."
if eval "$INSTALAR_CMD"; then
    echo "¡Instalación exitosa de SSH!"
else
    echo "Error crítico: Falló la instalación de SSH."
    exit 1
fi

# 6. Configurar, habilitar y arrancar el servicio de forma persistente
echo "Configurando el servicio para que inicie con el sistema..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable "$SERVICIO"
    systemctl start "$SERVICIO"
    
    # Verificación final del estado
    if systemctl is-active --quiet "$SERVICIO"; then
        echo "El servicio SSH está activo y funcionando correctamente."
    else
        echo "Error: El servicio SSH se instaló pero no se pudo iniciar."
        exit 1
    fi
else
    # Alternativa para sistemas antiguos sin systemd
    service "$SERVICIO" start
    chkconfig "$SERVICIO" on 2>/dev/null || update-rc.d "$SERVICIO" defaults
    echo "Servicio SSH iniciado mediante el gestor tradicional."
fi

# 7. Resumen de conectividad para el usuario
echo "=================================================="
echo "¡Proceso finalizado con éxito!"
echo "Para conectarte a esta máquina, usa:"
echo "ssh tu_usuario@$(hostname -I | awk '{print $1}')"
echo "=================================================="
