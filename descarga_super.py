import os
import time
import random
import threading
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

class ScraperAutosConfigurable:
    def __init__(self, lista_urls, carpeta_salida="autos", max_workers=5, espera_min=0.5, espera_max=2.0):
        self.lista_urls = lista_urls
        self.carpeta_salida = carpeta_salida
        self.max_workers = max_workers
        self.espera_min = espera_min
        self.espera_max = espera_max
        self.log_file = "autos_descargados.log"
        self.lock = threading.Lock()  # Bloqueo para evitar colisiones al escribir en el log
        
        if not os.path.exists(self.carpeta_salida):
            os.makedirs(self.carpeta_salida)

    def obtener_procesados(self):
        if os.path.exists(self.log_file):
            with open(self.log_file, "r") as f:
                return set(line.strip() for line in f)
        return set()

    def descargar_url(self, url):
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        
        try:
            # Retardo aleatorio para comportamiento humanoide
            time.sleep(random.uniform(self.espera_min, self.espera_max))
            
            response = requests.get(url, headers=headers, timeout=15)
            
            if response.status_code == 200:
                path_parts = [p for p in url.split('/') if p]
                nombre_archivo = f"{path_parts[-1]}.html"
                ruta = os.path.join(self.carpeta_salida, nombre_archivo)
                
                with open(ruta, "w", encoding="utf-8") as f:
                    f.write(response.text)
                
                # Registrar de forma segura con hilos
                with self.lock:
                    with open(self.log_file, "a") as f:
                        f.write(url + "\n")
                
                return f"ÉXITO: {url}"
            else:
                return f"ERROR {response.status_code}: {url}"
                
        except Exception as e:
            return f"CRÍTICO en {url}: {e}"

    def ejecutar(self):
        procesados = self.obtener_procesados()
        pendientes = [u for u in self.lista_urls if u not in procesados]
        
        total_pendientes = len(pendientes)
        if not pendientes:
            print("No hay nuevas URLs pendientes de descarga.")
            return

        print(f"Iniciando descarga de {total_pendientes} vehículos con {self.max_workers} hilos...\n")
        
        # Usamos as_completed para imprimir el progreso EN TIEMPO REAL
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
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
