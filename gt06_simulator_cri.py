#!/usr/bin/env python3
"""
Simulador de dispositivos GT06 para pruebas con Traccar (versión CLI/consola).

Version adaptada para Termux, Linux, macOS o Windows sin necesidad de Tkinter.
Permite agregar multiples dispositivos simulados, cada uno con su propio
IMEI generado automaticamente, y configurar la IP y puerto del servidor
Traccar al que se conecta cada uno. Cada dispositivo simulado hace login
con el protocolo GT06, y luego envia heartbeats y paquetes de posicion
GPS periodicamente, simulando un pequeno recorrido (random walk) a partir
de un punto de partida.

Requiere: Python 3 (sin dependencias graficas).
Uso: python3 gt06_simulator_cli.py
"""

import csv
import math
import os
import random
import socket
import struct
import threading
import time
import queue
from datetime import datetime, timezone

# --------------------------------------------------------------------------
# Utilidades de protocolo GT06 (identico al original)
# --------------------------------------------------------------------------

START_BITS = b"\x78\x78"
STOP_BITS = b"\x0d\x0a"

PROTO_LOGIN = 0x01
PROTO_LOCATION = 0x12
PROTO_HEARTBEAT = 0x13


def crc16_x25(data: bytes) -> int:
    """CRC-16/X25 (CRC-ITU) usado por el protocolo GT06."""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0x8408
            else:
                crc >>= 1
    return (~crc) & 0xFFFF


def luhn_check_digit(number: str) -> int:
    digits = [int(d) for d in number]
    total = 0
    for i, d in enumerate(reversed(digits)):
        if i % 2 == 0:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - (total % 10)) % 10


def generate_imei() -> str:
    """Genera un IMEI de 15 digitos con digito de control (Luhn) valido."""
    tac = "".join(random.choices("0123456789", k=8))
    serial = "".join(random.choices("0123456789", k=6))
    partial = tac + serial  # 14 digitos
    check = luhn_check_digit(partial)
    return partial + str(check)


def imei_to_bcd(imei: str) -> bytes:
    """Convierte un IMEI de 15 digitos a 8 bytes BCD (rellenando con 0 al inicio)."""
    padded = imei.zfill(16)
    out = bytearray()
    for i in range(0, 16, 2):
        high = int(padded[i])
        low = int(padded[i + 1])
        out.append((high << 4) | low)
    return bytes(out)


def build_packet(protocol: int, content: bytes, serial: int) -> bytes:
    inner = bytearray()
    inner.append(protocol)
    inner += content
    inner += struct.pack(">H", serial & 0xFFFF)
    length = len(inner) + 2  # + 2 bytes de CRC
    body = bytearray([length]) + inner
    crc = crc16_x25(bytes(body))
    return START_BITS + bytes(body) + struct.pack(">H", crc) + STOP_BITS


def build_login_packet(imei: str, serial: int) -> bytes:
    content = imei_to_bcd(imei)
    return build_packet(PROTO_LOGIN, content, serial)


def build_heartbeat_packet(serial: int) -> bytes:
    content = bytes([0x44, 0x04, 0x04, 0x00, 0x00])
    return build_packet(PROTO_HEARTBEAT, content, serial)


def build_location_packet(serial: int, lat: float, lon: float, speed_kmh: float, course: float) -> bytes:
    now = datetime.now(timezone.utc)
    dt_bytes = bytes([
        now.year % 100, now.month, now.day,
        now.hour, now.minute, now.second,
    ])
    gps_sat_byte = 0xC0 | 0x0C

    lat_raw = int(round(abs(lat) * 60 * 30000))
    lon_raw = int(round(abs(lon) * 60 * 30000))
    speed_byte = int(max(0, min(255, round(speed_kmh))))

    course_status = int(course) & 0x03FF
    if lon < 0:
        course_status |= (1 << 12)
    if lat < 0:
        course_status |= (1 << 13)
    course_status |= (1 << 15)

    mcc = 0x01A4
    mnc = 0x01
    lac = 0x0001
    cell_id = 0x000001

    content = bytearray()
    content += dt_bytes
    content.append(gps_sat_byte)
    content += struct.pack(">I", lat_raw)
    content += struct.pack(">I", lon_raw)
    content.append(speed_byte)
    content += struct.pack(">H", course_status)
    content += struct.pack(">H", mcc)
    content.append(mnc)
    content += struct.pack(">H", lac)
    content += cell_id.to_bytes(3, "big")

    return build_packet(PROTO_LOCATION, bytes(content), serial)


# --------------------------------------------------------------------------
# Simulador de un dispositivo individual (identico al original)
# --------------------------------------------------------------------------

class SimulatedDevice:
    def __init__(self, imei, host, port, interval, log_queue, base_lat=18.4861, base_lon=-69.9312):
        self.imei = imei
        self.host = host
        self.port = int(port)
        self.interval = float(interval)
        self.log_queue = log_queue
        self.lat = base_lat + random.uniform(-0.01, 0.01)
        self.lon = base_lon + random.uniform(-0.01, 0.01)
        self.course = random.uniform(0, 360)
        self.speed = random.uniform(0, 60)
        self.serial = 1
        self._stop_event = threading.Event()
        self._thread = None
        self.status = "Detenido"

    def log(self, msg):
        self.log_queue.put(f"[{self.imei}] {msg}")

    def _next_serial(self):
        s = self.serial
        self.serial = (self.serial + 1) & 0xFFFF
        return s

    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()

    def is_running(self):
        return self._thread is not None and self._thread.is_alive()

    def _walk(self):
        self.course = (self.course + random.uniform(-25, 25)) % 360
        self.speed = max(0, min(80, self.speed + random.uniform(-10, 10)))
        dist_deg = (self.speed / 3600.0) * self.interval / 111.0
        rad = math.radians(self.course)
        self.lat += dist_deg * math.cos(rad)
        self.lon += dist_deg * math.sin(rad)

    def _run(self):
        self.status = "Conectando..."
        sock = None
        try:
            sock = socket.create_connection((self.host, self.port), timeout=5)
            sock.settimeout(2)
            self.status = "Conectado"
            self.log(f"Conectado a {self.host}:{self.port}")

            login_pkt = build_login_packet(self.imei, self._next_serial())
            sock.sendall(login_pkt)
            try:
                resp = sock.recv(64)
                self.log(f"Login enviado, respuesta: {resp.hex()}")
            except socket.timeout:
                self.log("Login enviado (sin respuesta, continuando)")

            last_location = 0
            last_heartbeat = 0
            self.status = "Activo"

            while not self._stop_event.is_set():
                now = time.time()

                if now - last_location >= self.interval:
                    self._walk()
                    pkt = build_location_packet(
                        self._next_serial(), self.lat, self.lon, self.speed, self.course
                    )
                    sock.sendall(pkt)
                    self.log(f"Posicion enviada lat={self.lat:.5f} lon={self.lon:.5f} "
                             f"vel={self.speed:.1f}km/h curso={self.course:.0f}")
                    last_location = now

                if now - last_heartbeat >= max(self.interval * 3, 30):
                    hb = build_heartbeat_packet(self._next_serial())
                    sock.sendall(hb)
                    self.log("Heartbeat enviado")
                    last_heartbeat = now

                try:
                    sock.settimeout(1)
                    data = sock.recv(64)
                    if not data:
                        self.log("El servidor cerro la conexion")
                        break
                except socket.timeout:
                    pass

        except Exception as e:
            self.log(f"Error: {e}")
            self.status = "Error"
        finally:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass
            if self.status not in ("Error",):
                self.status = "Detenido"
            self.log("Desconectado")


# --------------------------------------------------------------------------
# Interfaz de consola (reemplaza la GUI de Tkinter)
# --------------------------------------------------------------------------

class ConsoleApp:
    def __init__(self):
        self.log_queue = queue.Queue()
        self.devices = {}      # row_id -> SimulatedDevice
        self.order = []        # orden de insercion de row_ids
        self._row_counter = 0
        self._log_thread_stop = threading.Event()
        self._log_thread = threading.Thread(target=self._log_worker, daemon=True)
        self._log_thread.start()

    # ---------------- Utilidades ----------------

    def clear(self):
        os.system("clear" if os.name != "nt" else "cls")

    def _log_worker(self):
        # Imprime mensajes de log en cuanto llegan, en segundo plano
        while not self._log_thread_stop.is_set():
            try:
                msg = self.log_queue.get(timeout=0.3)
                print(msg)
            except queue.Empty:
                continue

    def input_default(self, prompt, default):
        val = input(f"{prompt} [{default}]: ").strip()
        return val if val else str(default)

    # ---------------- Menu principal ----------------

    def run(self):
        print("=== Simulador GT06 para Traccar (CLI) ===")
        while True:
            print("\n--- Menu ---")
            print("1) Agregar dispositivo(s)")
            print("2) Listar dispositivos")
            print("3) Iniciar dispositivo(s)")
            print("4) Detener dispositivo(s)")
            print("5) Iniciar todos")
            print("6) Detener todos")
            print("7) Eliminar dispositivo(s)")
            print("8) Editar dispositivo")
            print("9) Exportar lista (CSV)")
            print("10) Importar lista (CSV)")
            print("0) Salir")
            choice = input("Elige una opcion: ").strip()

            if choice == "1":
                self.add_devices()
            elif choice == "2":
                self.list_devices()
            elif choice == "3":
                self.start_selected()
            elif choice == "4":
                self.stop_selected()
            elif choice == "5":
                self.start_all()
            elif choice == "6":
                self.stop_all()
            elif choice == "7":
                self.remove_selected()
            elif choice == "8":
                self.edit_device()
            elif choice == "9":
                self.export_list()
            elif choice == "10":
                self.import_list()
            elif choice == "0":
                self.stop_all()
                print("Saliendo...")
                self._log_thread_stop.set()
                break
            else:
                print("Opcion invalida.")

    # ---------------- Acciones ----------------

    def add_devices(self):
        host = self.input_default("IP servidor", "127.0.0.1")
        port = self.input_default("Puerto", "5023")
        interval = self.input_default("Intervalo (s)", "5")
        qty = self.input_default("Cantidad a agregar", "1")
        base_lat = self.input_default("Latitud inicial", "18.4861")
        base_lon = self.input_default("Longitud inicial", "-69.9312")

        try:
            qty_n = int(qty)
            if qty_n < 1:
                raise ValueError
            int(port)
            float(interval)
            base_lat_f = float(base_lat)
            base_lon_f = float(base_lon)
        except ValueError:
            print("Error: cantidad, puerto, intervalo, latitud o longitud invalidos.")
            return

        for _ in range(qty_n):
            imei = generate_imei()
            row_id = f"dev{self._row_counter}"
            self._row_counter += 1
            device = SimulatedDevice(
                imei, host, port, interval, self.log_queue,
                base_lat=base_lat_f, base_lon=base_lon_f,
            )
            self.devices[row_id] = device
            self.order.append(row_id)
            print(f"Agregado {row_id}: IMEI={imei} host={host}:{port} intervalo={interval}s")

    def _select_ids(self, prompt="IDs (ej: dev0,dev2 o 'all')"):
        if not self.order:
            print("No hay dispositivos.")
            return []
        self.list_devices()
        raw = input(f"{prompt}: ").strip()
        if not raw:
            return []
        if raw.lower() == "all":
            return list(self.order)
        ids = [x.strip() for x in raw.split(",")]
        return [i for i in ids if i in self.devices]

    def list_devices(self):
        if not self.order:
            print("No hay dispositivos agregados.")
            return
        print(f"{'ID':6} {'IMEI':17} {'Host':15} {'Puerto':7} {'Interv':7} {'Lat':10} {'Lon':11} {'Estado'}")
        for row_id in self.order:
            dev = self.devices[row_id]
            print(f"{row_id:6} {dev.imei:17} {dev.host:15} {dev.port:<7} {dev.interval:<7} "
                  f"{dev.lat:<10.5f} {dev.lon:<11.5f} {dev.status}")

    def start_selected(self):
        for row_id in self._select_ids():
            self.devices[row_id].start()
            print(f"{row_id} iniciado.")

    def stop_selected(self):
        for row_id in self._select_ids():
            self.devices[row_id].stop()
            print(f"{row_id} detenido.")

    def start_all(self):
        for dev in self.devices.values():
            dev.start()
        print("Todos los dispositivos iniciados.")

    def stop_all(self):
        for dev in self.devices.values():
            dev.stop()
        print("Todos los dispositivos detenidos.")

    def remove_selected(self):
        for row_id in self._select_ids():
            dev = self.devices.get(row_id)
            if dev:
                dev.stop()
                del self.devices[row_id]
                self.order.remove(row_id)
                print(f"{row_id} eliminado.")

    def edit_device(self):
        ids = self._select_ids("ID del dispositivo a editar")
        if not ids:
            return
        row_id = ids[0]
        dev = self.devices[row_id]
        print("Campos editables: host, port, interval, lat, lon")
        field = input("Campo a editar: ").strip().lower()
        if field not in ("host", "port", "interval", "lat", "lon"):
            print("Campo invalido.")
            return
        new_val = input(f"Nuevo valor para {field}: ").strip()
        try:
            if field == "port":
                dev.port = int(new_val)
            elif field == "interval":
                dev.interval = float(new_val)
            elif field == "host":
                dev.host = new_val
            elif field == "lat":
                dev.lat = float(new_val)
            elif field == "lon":
                dev.lon = float(new_val)
            print(f"{row_id}.{field} actualizado a {new_val}")
        except ValueError:
            print("Valor invalido.")

    # ---------------- Exportar / Importar ----------------

    def export_list(self):
        if not self.devices:
            print("No hay dispositivos para exportar.")
            return
        path = input("Ruta del archivo CSV a guardar (ej: dispositivos.csv): ").strip()
        if not path:
            print("Ruta vacia, cancelado.")
            return
        try:
            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["imei", "host", "port", "interval", "lat", "lon"])
                for row_id in self.order:
                    dev = self.devices[row_id]
                    writer.writerow([dev.imei, dev.host, dev.port, dev.interval, dev.lat, dev.lon])
            print(f"Lista exportada a: {path}")
        except Exception as e:
            print(f"No se pudo exportar: {e}")

    def import_list(self):
        path = input("Ruta del archivo CSV a importar: ").strip()
        if not path:
            print("Ruta vacia, cancelado.")
            return
        try:
            with open(path, "r", newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                count = 0
                for row in reader:
                    row_id = f"dev{self._row_counter}"
                    self._row_counter += 1
                    device = SimulatedDevice(
                        row["imei"], row["host"], row["port"], row["interval"],
                        self.log_queue,
                        base_lat=float(row["lat"]), base_lon=float(row["lon"]),
                    )
                    device.lat = float(row["lat"])
                    device.lon = float(row["lon"])
                    self.devices[row_id] = device
                    self.order.append(row_id)
                    count += 1
            print(f"Se importaron {count} dispositivos.")
        except Exception as e:
            print(f"No se pudo importar: {e}")


if __name__ == "__main__":
    app = ConsoleApp()
    try:
        app.run()
    except KeyboardInterrupt:
        app.stop_all()
        print("\nInterrumpido por el usuario. Saliendo...")
