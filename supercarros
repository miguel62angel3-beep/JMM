import os
import time
import random
import requests
from concurrent.futures import ThreadPoolExecutor


class ScraperAutosConfigurable:
    def __init__(self, lista_urls, carpeta_salida="autos", max_workers=5, espera_min=0.5, espera_max=2.0):
        self.lista_urls = lista_urls
        self.carpeta_salida = carpeta_salida
        self.max_workers = max_workers
        self.espera_min = espera_min
        self.espera_max = espera_max
        self.log_file = "autos_descargados.log"
       
        if not os.path.exists(self.carpeta_salida):
            os.makedirs(self.carpeta_salida)


    def obtener_procesados(self):
        # Verifica qué archivos ya se han procesado exitosamente
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
                # Extraemos el ID del vehículo (asumiendo formato /marca-modelo/id/)
                # Esto genera un nombre de archivo único como '1500337.html'
                path_parts = [p for p in url.split('/') if p]
                nombre_archivo = f"{path_parts[-1]}.html"
                ruta = os.path.join(self.carpeta_salida, nombre_archivo)
               
                with open(ruta, "w", encoding="utf-8") as f:
                    f.write(response.text)
               
                # Registrar que esta URL ya está completada
                with open(self.log_file, "a") as f:
                    f.write(url + "\n")
                return f"OK: {url}"
            else:
                return f"Error {response.status_code}: {url}"
               
        except Exception as e:
            return f"Error crítico en {url}: {e}"


    def ejecutar(self):
        procesados = self.obtener_procesados()
        # Filtramos los que ya están en el log para asegurar que no haya repeticiones
        pendientes = [u for u in self.lista_urls if u not in procesados]
       
        if not pendientes:
            print("No hay nuevas URLs pendientes de descarga.")
            return


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

