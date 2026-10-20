"""Local design preview: real firmware C++ renderer, explicitly synthetic audio.

The app uses the same C ABI directly; this HTTP adapter is for browser design QA.
Bound to loopback, no disk writes, shell execution, BLE or device control.
"""
import argparse
import ctypes as c
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]
ORIGINS = {"http://localhost:49468", "http://127.0.0.1:49468"}
FRAME_BYTES = 1024


class Engine:
    def __init__(self, library):
        self.lib = c.CDLL(str(library))
        self.lib.bdk_led_create.restype = c.c_void_p
        self.lib.bdk_led_destroy.argtypes = [c.c_void_p]
        self.lib.bdk_led_settings.argtypes = [c.c_void_p, c.POINTER(c.c_uint8), c.c_int]
        self.lib.bdk_led_render.argtypes = [c.c_void_p, c.POINTER(c.c_float), c.c_uint8,
                                          c.c_int, c.POINTER(c.c_uint8), c.c_int]
        self.sessions = {}

    def frames(self, request):
        key, values, count = request["session"], request["settings"], request.get("count", 60)
        if not isinstance(key, str) or not 1 <= len(key) <= 100:
            raise ValueError("Invalid session")
        if (not isinstance(values, list) or len(values) != 10 or
                any(type(v) is not int or v < 0 or v > 255 for v in values) or
                values[0] > 21 or values[1] > 100 or values[2] > 100 or values[9] > 4):
            raise ValueError("Invalid LED settings")
        if type(count) is not int or not 1 <= count <= 120:
            raise ValueError("Invalid frame count")
        now = time.monotonic()
        for old in list(self.sessions):
            if now - self.sessions[old][2] > 120:
                self.lib.bdk_led_destroy(self.sessions.pop(old)[0])
        if key not in self.sessions:
            if len(self.sessions) >= 32:
                oldest = min(self.sessions, key=lambda k: self.sessions[k][2])
                self.lib.bdk_led_destroy(self.sessions.pop(oldest)[0])
            ctx = self.lib.bdk_led_create()
            if not ctx:
                raise RuntimeError("Renderer allocation failed")
            self.sessions[key] = [ctx, 0, now]
        state = self.sessions[key]
        settings = (c.c_uint8 * 10)(*values)
        if self.lib.bdk_led_settings(state[0], settings, 10) != 1:
            raise ValueError("Renderer rejected settings")
        out, frames = (c.c_uint8 * FRAME_BYTES)(), bytearray()
        for _ in range(count):
            # Deliberately simulated input; effects themselves run unchanged.
            n = state[1]
            bass = .25 + .65 * max(0., math.cos(n * math.tau / 24)) ** 4
            mid = .30 + .24 * math.sin(n * .14) ** 2
            high = .12 + .27 * math.cos(n * .19) ** 2
            db = lambda v: 20 * math.log10(max(.001, v))
            audio = (c.c_float * 7)(bass, mid, high, db(bass), db(mid), db(high), bass)
            flags = 2 | (1 if n % 24 == 0 else 0)
            if self.lib.bdk_led_render(state[0], audio, flags, 0, out, FRAME_BYTES) != FRAME_BYTES:
                raise RuntimeError("Renderer rejected frame")
            frames.extend(out)
            state[1] += 1
        state[2] = now
        return bytes(frames)

    def close(self):
        for ctx, _, _ in self.sessions.values():
            self.lib.bdk_led_destroy(ctx)
        self.sessions.clear()


class Handler(BaseHTTPRequestHandler):
    engine: Engine

    def cors(self):
        origin = self.headers.get("Origin")
        if origin in ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")
        self.send_header("Cache-Control", "no-store")

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        if self.path != "/frames" or self.headers.get("Origin") not in ORIGINS:
            self.send_error(403)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 1 <= length <= 2048:
                raise ValueError("Request too large")
            result = self.engine.frames(json.loads(self.rfile.read(length)))
        except (ValueError, KeyError, TypeError) as error:
            self.send_response(400)
            self.cors()
            self.end_headers()
            self.wfile.write(str(error).encode())
            return
        self.send_response(200)
        self.cors()
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(result)))
        self.send_header("X-BDK-Input", "synthetic-audio")
        self.end_headers()
        self.wfile.write(result)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path,
                        default=ROOT / "build/native_renderer/Release/bdk_led_engine.dll")
    parser.add_argument("--port", type=int, default=49469)
    args = parser.parse_args()
    Handler.engine = Engine(args.library)
    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Firmware renderer preview http://127.0.0.1:{args.port} (synthetic input)", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        Handler.engine.close()
