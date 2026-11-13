#!/usr/bin/env python3
"""Отдаёт процент загрузки сетевого интерфейса (Mbit/s / CAP) на :8090.

Доступ ограничен на уровне nftables (только IP панели).
"""
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

IFACE = "ens18"
CAP = 1000  # Mbit/s


def mbit():
    def total():
        base = f"/sys/class/net/{IFACE}/statistics"
        return int(open(base + "/rx_bytes").read()) + int(open(base + "/tx_bytes").read())

    a = total()
    time.sleep(0.4)
    b = total()
    return max(0.0, (b - a) * 8 / 0.4 / 1_000_000)


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        pct = max(0, min(100, round(mbit() / CAP * 100)))
        body = str(pct).encode()
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8090), H).serve_forever()
