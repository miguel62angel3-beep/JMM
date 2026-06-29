import os
import time
import sys
import re
import requests
import xml.etree.ElementTree as ET

# Configuración básica
SITEMAP_URL = "https://www.supercarros.com/sitemap.xml"
DELAY = 1.0  # Ritmo estricto de 1 segundo entre peticiones

# Estructura de carpetas
FOLDER_DEALERS = "dealers"
FOLDER_PUBLICACIONES = "publicaciones"

# Crear los directorios si no existen
os.makedirs(FOLDER_DEALERS, exist_ok=True)
os.makedirs(FOLDER_PUBLICACIONES, exist_ok=True)

# User-Agent realista para emular un navegador humano estándar
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

def obtener_urls_sitemap(url):
    """Descarga el sitemap y extrae todas las URLs válidas."""
    print(f"[*] Descargando y parseando el sitemap: {url}...")
    try:
        response = requests.get(url, headers=HEADERS, timeout=15)
        response.raise_for_status()
        
        # Eliminar namespaces del XML para facilitar la lectura de las etiquetas <loc>
        xml_clean = re.sub(r'\sxmlns="[^"]+"', '', response.text, count=1)
        root = ET.fromstring(xml_clean.encode('utf-8'))
        
        urls = [loc.text for loc in root.findall(".//loc") if loc.text]
        return urls
    except Exception as e:
        print(f"[!] Error crítico al obtener el sitemap: {e}")
        sys.exit(1)

def clasificar_url(url):
    """Determina la carpeta de destino y el nombre del archivo basado en la estructura de la URL."""
    # Ejemplo: https://www.supercarros.com/dealers/racemotors/
    if "/dealers/" in url:
        partes = url.strip("/").split("/")
        nombre_archivo = f"{partes[-1]}.txt"
        return FOLDER_DEALERS, nombre_archivo
    
    # Ejemplo: https://www.supercarros.com/volkswagen-id/1608399/
    # Detecta el patrón final numérico clásico de una publicación
    partes = url.strip("/").split("/")
    if partes and partes[-1].isdigit():
        nombre_archivo = f"{partes[-1]}.txt"
        return FOLDER_PUBLICACIONES, nombre_archivo

    # Retorna None si no encaja en tus dos criterios específicos
    return None, None

def guardar_contenido(carpeta, archivo, texto):
    """Escribe de manera segura el contenido extraído en un archivo de texto."""
    ruta_completa = os.path.join(carpeta, archivo)
    with open(ruta_completa, "w", encoding="utf-8") as f:
        f.write(texto)

def scraping_proceso():
    # 1. Recuperar los enlaces del archivo maestro sitemap.xml
    todas_las_urls = obtener_urls_sitemap(SITEMAP_URL)
    
    # Filtrar únicamente las URLs que correspondan a dealers o publicaciones de interés
    urls_filtradas = []
    for url in todas_las_urls:
        carpeta, _ = clasificar_url(url)
        if carpeta:
            urls_filtradas.append(url)
            
    total_enlaces = len(urls_filtradas)
    print(f"[+] Se encontraron {total_enlaces} enlaces listos para descargar y clasificar.")
    
    if total_enlaces == 0:
        print("[*] No hay enlaces que coincidan con los criterios establecidos.")
        return

    # 2. Bucle principal de ejecución paso a paso
    for index, url in enumerate(urls_filtradas):
        enlaces_restantes = total_enlaces - index
        
        # Mostrar barra de progreso simple en consola
        sys.stdout.write(f"\r[*] Procesando... Enlaces restantes: {enlaces_restantes} | Descargando: {url[:60]}... ")
        sys.stdout.flush()

        carpeta_destino, nombre_archivo = clasificar_url(url)
        
        try:
            # Petición controlada del HTML/Texto de la página web
            response = requests.get(url, headers=HEADERS, timeout=10)
            
            # --- DETECTAR BLOQUEOS ---
            # Si responde un código 429 (Demasiadas peticiones) o 403 (Prohibido/Cloudflare Antirrobos)
            if response.status_code in [403, 429]:
                print(f"\n\n[CRÍTICO] Bloqueo detectado (Código HTTP {response.status_code}). Deteniendo el script inmediatamente para proteger la cuenta/IP.")
                break
                
            response.raise_for_status()
            
            # Guardar el contenido plano en su respectiva ubicación
            guardar_contenido(carpeta_destino, nombre_archivo, response.text)
            
        except requests.exceptions.HTTPError as http_err:
            # Errores comunes de red como enlaces rotos (404) o caídas internas (500)
            print(f"\n[Error HTTP] No se pudo descargar {url} -> {http_err}")
        except requests.exceptions.RequestException as req_err:
            # Captura fallos de timeout o pérdida total de internet
            print(f"\n[Error de Red] Conexión fallida en {url} -> {req_err}")
            
        # Respetar el límite de velocidad asignado por segundo
        time.sleep(DELAY)

    print(f"\n\n[✓] Proceso de scraping finalizado de manera controlada.")

if __name__ == "__main__":
    scraping_proceso()
