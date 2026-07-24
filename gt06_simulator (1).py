#!/usr/bin/env python3
"""
Simulador de dispositivos GT06 para pruebas con Traccar.

Permite agregar múltiples dispositivos simulados, cada uno con su propio
IMEI generado automáticamente, y configurar la IP y puerto del servidor
Traccar al que se conecta cada uno. Cada dispositivo simulado hace login
con el protocolo GT06, y luego envía heartbeats y paquetes de posición
GPS periódicamente, simulando un pequeño recorrido (random walk) a partir
de un punto de partida.

Requiere: Python 3 con Tkinter (en Linux puede requerir instalar
python3-tk: `sudo apt install python3-tk`).

Uso: python3 gt06_simulator.py
"""

import csv
import random
import socket
import struct
import threading
import time
import queue
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog
from datetime import datetime, timezone

# --------------------------------------------------------------------------
# Utilidades de protocolo GT06
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
    # Recorremos de derecha a izquierda; duplicamos cada segunda cifra
    for i, d in enumerate(reversed(digits)):
        if i % 2 == 0:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - (total % 10)) % 10


def generate_imei() -> str:
    """Genera un IMEI de 15 dígitos con dígito de control (Luhn) válido."""
    tac = "".join(random.choices("0123456789", k=8))
    serial = "".join(random.choices("0123456789", k=6))
    partial = tac + serial  # 14 dígitos
    check = luhn_check_digit(partial)
    return partial + str(check)


def imei_to_bcd(imei: str) -> bytes:
    """Convierte un IMEI de 15 dígitos a 8 bytes BCD (rellenando con 0 al inicio)."""
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
    # Byte de info de terminal, nivel de batería, señal GSM (valores de ejemplo razonables)
    content = bytes([0x44, 0x04, 0x04, 0x00, 0x00])
    return build_packet(PROTO_HEARTBEAT, content, serial)


def build_location_packet(serial: int, lat: float, lon: float, speed_kmh: float, course: float) -> bytes:
    now = datetime.now(timezone.utc)
    dt_bytes = bytes([
        now.year % 100, now.month, now.day,
        now.hour, now.minute, now.second,
    ])

    gps_sat_byte = 0xC0 | 0x0C  # longitud fija (0xC) + 12 satélites (valor de ejemplo)

    lat_raw = int(round(abs(lat) * 60 * 30000))
    lon_raw = int(round(abs(lon) * 60 * 30000))

    speed_byte = int(max(0, min(255, round(speed_kmh))))

    course_status = int(course) & 0x03FF  # bits 0-9: curso 0-359
    if lon < 0:
        course_status |= (1 << 12)  # Oeste
    if lat < 0:
        course_status |= (1 << 13)  # Sur
    course_status |= (1 << 15)      # GPS con posición válida (fix)

    mcc = 0x01A4      # ejemplo (no crítico para pruebas)
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
# Simulador de un dispositivo individual
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
        # Pequeño paseo aleatorio para simular movimiento real
        self.course = (self.course + random.uniform(-25, 25)) % 360
        self.speed = max(0, min(80, self.speed + random.uniform(-10, 10)))
        dist_deg = (self.speed / 3600.0) * self.interval / 111.0  # aprox grados
        import math
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
                    self.log(f"Posición enviada lat={self.lat:.5f} lon={self.lon:.5f} "
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
                        self.log("El servidor cerró la conexión")
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
# Interfaz gráfica
# --------------------------------------------------------------------------

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Simulador GT06 para Traccar")
        self.geometry("980x600")

        self.log_queue = queue.Queue()
        self.devices = {}  # row_id -> SimulatedDevice
        self._row_counter = 0

        self._build_ui()
        self.after(200, self._poll_log_queue)
        self.after(1000, self._refresh_status)

    # ---------------- UI ----------------
    def _build_ui(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")

        ttk.Label(top, text="IP servidor:").grid(row=0, column=0, sticky="w")
        self.host_var = tk.StringVar(value="127.0.0.1")
        ttk.Entry(top, textvariable=self.host_var, width=15).grid(row=0, column=1, padx=4)

        ttk.Label(top, text="Puerto:").grid(row=0, column=2, sticky="w")
        self.port_var = tk.StringVar(value="5023")
        ttk.Entry(top, textvariable=self.port_var, width=8).grid(row=0, column=3, padx=4)

        ttk.Label(top, text="Intervalo (s):").grid(row=0, column=4, sticky="w")
        self.interval_var = tk.StringVar(value="5")
        ttk.Entry(top, textvariable=self.interval_var, width=6).grid(row=0, column=5, padx=4)

        ttk.Label(top, text="Cantidad a agregar:").grid(row=0, column=6, sticky="w")
        self.qty_var = tk.StringVar(value="1")
        ttk.Entry(top, textvariable=self.qty_var, width=6).grid(row=0, column=7, padx=4)

        ttk.Button(top, text="Agregar dispositivo(s)", command=self.add_devices).grid(
            row=0, column=8, padx=8
        )

        ttk.Label(top, text="Latitud inicial:").grid(row=1, column=0, sticky="w", pady=(6, 0))
        self.lat_var = tk.StringVar(value="18.4861")
        ttk.Entry(top, textvariable=self.lat_var, width=15).grid(row=1, column=1, padx=4, pady=(6, 0))

        ttk.Label(top, text="Longitud inicial:").grid(row=1, column=2, sticky="w", pady=(6, 0))
        self.lon_var = tk.StringVar(value="-69.9312")
        ttk.Entry(top, textvariable=self.lon_var, width=15).grid(row=1, column=3, padx=4, pady=(6, 0))

        ttk.Label(top, text="(dispersión aleatoria ±0.01° por dispositivo)").grid(
            row=1, column=4, columnspan=3, sticky="w", pady=(6, 0)
        )

        ttk.Button(top, text="Exportar lista", command=self.export_list).grid(
            row=1, column=8, padx=8, pady=(6, 0)
        )
        ttk.Button(top, text="Importar lista", command=self.import_list).grid(
            row=1, column=9, padx=(0, 8), pady=(6, 0)
        )

        mid = ttk.Frame(self, padding=(8, 0))
        mid.pack(fill="both", expand=True)

        columns = ("imei", "host", "port", "interval", "lat", "lon", "status")
        self.tree = ttk.Treeview(mid, columns=columns, show="headings", height=15)
        headers = {
            "imei": "IMEI",
            "host": "IP",
            "port": "Puerto",
            "interval": "Intervalo (s)",
            "lat": "Latitud",
            "lon": "Longitud",
            "status": "Estado",
        }
        for col in columns:
            self.tree.heading(col, text=headers[col])
            self.tree.column(col, width=150 if col == "imei" else 100, anchor="center")
        self.tree.pack(fill="both", expand=True, side="left")

        scroll = ttk.Scrollbar(mid, orient="vertical", command=self.tree.yview)
        scroll.pack(side="left", fill="y")
        self.tree.configure(yscrollcommand=scroll.set)

        self.tree.bind("<Double-1>", self._on_double_click)

        btns = ttk.Frame(self, padding=8)
        btns.pack(fill="x")
        ttk.Button(btns, text="Iniciar seleccionados", command=self.start_selected).pack(side="left", padx=4)
        ttk.Button(btns, text="Detener seleccionados", command=self.stop_selected).pack(side="left", padx=4)
        ttk.Button(btns, text="Iniciar todos", command=self.start_all).pack(side="left", padx=4)
        ttk.Button(btns, text="Detener todos", command=self.stop_all).pack(side="left", padx=4)
        ttk.Button(btns, text="Eliminar seleccionados", command=self.remove_selected).pack(side="left", padx=4)

        log_frame = ttk.LabelFrame(self, text="Registro", padding=4)
        log_frame.pack(fill="both", expand=False, padx=8, pady=8)
        self.log_text = tk.Text(log_frame, height=10, state="disabled")
        self.log_text.pack(fill="both", expand=True)

    # ---------------- Acciones ----------------
    def add_devices(self):
        try:
            qty = int(self.qty_var.get())
            if qty < 1:
                raise ValueError
        except ValueError:
            messagebox.showerror("Error", "La cantidad debe ser un número entero positivo.")
            return

        host = self.host_var.get().strip()
        port = self.port_var.get().strip()
        interval = self.interval_var.get().strip()
        base_lat = self.lat_var.get().strip()
        base_lon = self.lon_var.get().strip()

        try:
            int(port)
            float(interval)
            base_lat_f = float(base_lat)
            base_lon_f = float(base_lon)
        except ValueError:
            messagebox.showerror("Error", "Puerto, intervalo, latitud o longitud inválidos.")
            return

        for _ in range(qty):
            imei = generate_imei()
            row_id = f"dev{self._row_counter}"
            self._row_counter += 1
            device = SimulatedDevice(
                imei, host, port, interval, self.log_queue,
                base_lat=base_lat_f, base_lon=base_lon_f,
            )
            self.devices[row_id] = device
            self.tree.insert(
                "", "end", iid=row_id,
                values=(imei, host, port, interval,
                        f"{device.lat:.6f}", f"{device.lon:.6f}", device.status),
            )

    def _get_selected_ids(self):
        return list(self.tree.selection())

    def start_selected(self):
        for row_id in self._get_selected_ids():
            self.devices[row_id].start()

    def stop_selected(self):
        for row_id in self._get_selected_ids():
            self.devices[row_id].stop()

    def start_all(self):
        for dev in self.devices.values():
            dev.start()

    def stop_all(self):
        for dev in self.devices.values():
            dev.stop()

    def remove_selected(self):
        for row_id in self._get_selected_ids():
            dev = self.devices.get(row_id)
            if dev:
                dev.stop()
                del self.devices[row_id]
            self.tree.delete(row_id)

    def _on_double_click(self, event):
        row_id = self.tree.identify_row(event.y)
        col = self.tree.identify_column(event.x)
        if not row_id or row_id not in self.devices:
            return
        col_index = int(col.replace("#", "")) - 1
        col_names = ("imei", "host", "port", "interval", "lat", "lon", "status")
        col_name = col_names[col_index]
        if col_name in ("status", "imei"):
            return  # no editables

        dev = self.devices[row_id]
        current = getattr(dev, col_name)
        new_val = simpledialog.askstring("Editar", f"Nuevo valor para {col_name}:", initialvalue=str(current))
        if new_val is None:
            return
        try:
            if col_name == "port":
                dev.port = int(new_val)
            elif col_name == "interval":
                dev.interval = float(new_val)
            elif col_name == "host":
                dev.host = new_val
            elif col_name == "lat":
                dev.lat = float(new_val)
            elif col_name == "lon":
                dev.lon = float(new_val)
        except ValueError:
            messagebox.showerror("Error", "Valor inválido.")
            return

        values = list(self.tree.item(row_id, "values"))
        values[col_index] = new_val
        self.tree.item(row_id, values=values)

    # ---------------- Exportar / Importar ----------------
    def export_list(self):
        if not self.devices:
            messagebox.showinfo("Exportar", "No hay dispositivos para exportar.")
            return
        path = filedialog.asksaveasfilename(
            defaultextension=".csv",
            filetypes=[("CSV", "*.csv"), ("Todos los archivos", "*.*")],
            title="Guardar lista de dispositivos",
        )
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["imei", "host", "port", "interval", "lat", "lon"])
                for row_id in self.tree.get_children():
                    dev = self.devices[row_id]
                    writer.writerow([dev.imei, dev.host, dev.port, dev.interval, dev.lat, dev.lon])
            messagebox.showinfo("Exportar", f"Lista exportada a:\n{path}")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo exportar: {e}")

    def import_list(self):
        path = filedialog.askopenfilename(
            filetypes=[("CSV", "*.csv"), ("Todos los archivos", "*.*")],
            title="Importar lista de dispositivos",
        )
        if not path:
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
                    # Usamos exactamente la posición guardada, sin dispersión aleatoria adicional
                    device.lat = float(row["lat"])
                    device.lon = float(row["lon"])
                    self.devices[row_id] = device
                    self.tree.insert(
                        "", "end", iid=row_id,
                        values=(device.imei, device.host, device.port, device.interval,
                                f"{device.lat:.6f}", f"{device.lon:.6f}", device.status),
                    )
                    count += 1
            messagebox.showinfo("Importar", f"Se importaron {count} dispositivos.")
        except Exception as e:
            messagebox.showerror("Error", f"No se pudo importar: {e}")

    # ---------------- Refresco periódico ----------------
    def _poll_log_queue(self):
        try:
            while True:
                msg = self.log_queue.get_nowait()
                self.log_text.configure(state="normal")
                self.log_text.insert("end", msg + "\n")
                self.log_text.see("end")
                self.log_text.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(200, self._poll_log_queue)

    def _refresh_status(self):
        for row_id, dev in self.devices.items():
            values = list(self.tree.item(row_id, "values"))
            values[6] = dev.status
            self.tree.item(row_id, values=values)
        self.after(1000, self._refresh_status)

    def destroy(self):
        for dev in self.devices.values():
            dev.stop()
        super().destroy()


if __name__ == "__main__":
    app = App()
    app.mainloop()
