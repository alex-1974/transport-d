#!/usr/bin/env python3
import http.server
import sys

payload = bytes(range(32))
received = bytearray()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        value = payload
        status = 200
        header = self.headers.get("Range", "")
        if header.startswith("bytes="):
            start, end = header[6:].split("-", 1)
            start = int(start)
            end = int(end) if end else len(payload) - 1
            if start >= len(payload):
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(payload)}")
                self.end_headers()
                return
            value = payload[start:end + 1]
            status = 206
        self.send_response(status)
        self.send_header("Content-Length", str(len(value)))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{start + len(value) - 1}/{len(payload)}")
        self.end_headers()
        self.wfile.write(value)

    def do_PUT(self):
        size = int(self.headers.get("Content-Length", "0"))
        received[:] = self.rfile.read(size)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()
        with open(sys.argv[1], "wb") as output:
            output.write(received)

    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), Handler)
server.serve_forever()
