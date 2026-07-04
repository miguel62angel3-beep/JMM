import requests
import xml.etree.ElementTree as ET
import os

def procesar_sitemap(url_sitemap):
    # 1. Descargar el contenido del sitemap
    print(f"Descargando {url_sitemap}...")
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'}
    response = requests.get(url_sitemap, headers=headers)
    
    if response.status_code != 200:
        print("Error al descargar el sitemap.")
        return

    # 2. Parsear el XML
    root = ET.fromstring(response.content)
    
    # Usamos sets para asegurar que no haya duplicados
    dealers = set()
    autos = set()
    
    # Namespace común en sitemaps
    ns = {'ns': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
    
    for url in root.findall('.//ns:loc', ns):
        link = url.text
        if "/dealers/" in link:
            dealers.add(link)
        else:
            autos.add(link)
    
    # 3. Guardar en archivos (sobrescribir o crear)
    with open('dealers.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(sorted(dealers)))
    
    with open('autos.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(sorted(autos)))
        
    print(f"Proceso finalizado.")
    print(f"Total dealers guardados: {len(dealers)}")
    print(f"Total autos guardados: {len(autos)}")

# Ejecución
url = "https://www.supercarros.com/sitemap.xml"
procesar_sitemap(url)        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # Lanzamos todas las tareas
            futuros = {executor.submit(self.descargar_url, url): url for url in pendientes}
            
            contador = 0
            for futuro in as_completed(futuros):
                contador += 1
                resultado = futuro.result()
                # Imprime el progreso actual (ej: [1/45] ÉXITO: http://...)
                print(f"[{contador}/{total_pendientes}] {resultado}")
            
        print("\nProceso completamente finalizado.")

# --- EJECUCIÓN ---
if __name__ == "__main__":
    if os.path.exists("autos.txt"):
        with open("autos.txt", "r") as f:
            urls_unicas = list(set(line.strip() for line in f if line.strip()))
        
        scraper = ScraperAutosConfigurable(
            lista_urls=urls_unicas,
            carpeta_salida="autos",
            max_workers=3,  # Puedes subirlo un poco si tu conexión aguanta
            espera_min=0.5,
            espera_max=2.0
        )
        scraper.ejecutar()
    else:
        print("Error: No se encontró el archivo 'autos.txt'.")


        print(f"Iniciando descarga de {len(pendientes)} vehículos con {self.max_workers} hilos...")
       
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            resultados = list(executor.map(self.descargar_url, pendientes))
           
        print("Proceso completado.")


# --- EJECUCIÓN ---
if __name__ == "__main__":
    if os.path.exists("autos.txt"):
        with open("autos.txt", "r") as f:
            # Eliminar duplicados de la lista inicial también
            urls_unicas = list(set(line.strip() for line in f if line.strip()))
       
        scraper = ScraperAutosConfigurable(
            lista_urls=urls_unicas,
            carpeta_salida="autos",
            max_workers=2,
            espera_min=0.5,
            espera_max=2.0
        )
        scraper.ejecutar()
    else:
        print("Error: No se encontró el archivo 'autos.txt'.")

