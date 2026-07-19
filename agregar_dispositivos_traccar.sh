#!/bin/bash

# ==========================================
# Configuración de credenciales y rutas
# ==========================================
USER="admin"
PASS="admin" # Cambia esto por tu contraseña real
URL_TRACCAR="http://127.0.0.1:8082/api/devices"

# ⚠️ IMPORTANTE: Debe ser el enlace "Raw" del archivo en GitHub
URL_GITHUB="https://raw.githubusercontent.com/miguel62angel3-beep/JMM/refs/heads/main/lista_de_dispositivos_a_simular.txt" 

echo "Descargando lista de IMEIs desde GitHub..."

# Descargamos el archivo, eliminamos posibles saltos de línea de Windows (\r) y guardamos en un archivo temporal
curl -s "$URL_GITHUB" | tr -d '\r' > /tmp/imeis_temp.txt

# Verificamos si la descarga fue exitosa y el archivo no está vacío
if [ ! -s /tmp/imeis_temp.txt ]; then
    echo "Error: No se pudo descargar el archivo de GitHub o está vacío. Revisa la URL."
    exit 1
fi

TOTAL=$(wc -l < /tmp/imeis_temp.txt)
echo "Se encontraron $TOTAL dispositivos. Iniciando inyección vía API..."

CONTADOR=0

# Leemos el archivo línea por línea
while IFS= read -r IMEI; do
    # Saltamos líneas vacías por precaución
    if [ -z "$IMEI" ]; then continue; fi

    ((CONTADOR++))
    
    # Le asignamos un nombre genérico basado en el número de fila, puedes cambiarlo si lo deseas
    NAME="Simulador_$CONTADOR"

    # Llamada a la API de Traccar (Guardamos el código HTTP de respuesta para verificar)
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$USER:$PASS" -X POST "$URL_TRACCAR" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$NAME\", \"uniqueId\":\"$IMEI\"}")

    # Validamos si la respuesta fue un éxito (200 o 201)
    if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 202 ]; then
        # Imprimir progreso cada 100 dispositivos para no saturar la pantalla
        if (( CONTADOR % 100 == 0 )); then
            echo "Progreso: $CONTADOR / $TOTAL dispositivos agregados..."
        fi
    else
        echo "Error al agregar el IMEI: $IMEI (Código HTTP de respuesta: $HTTP_STATUS)"
    fi

done < /tmp/imeis_temp.txt

# Limpieza del archivo temporal
rm /tmp/imeis_temp.txt

echo "=========================================="
echo "¡Proceso completado! Se enviaron $CONTADOR dispositivos a la base de datos."
echo "=========================================="
