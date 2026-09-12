"""Serves the web build with the headers Godot needs.

    python3 build/web/serve.py

The COOP/COEP pair is not optional: the export uses threads (for the audio
synthesis among other things), and a browser only grants SharedArrayBuffer to a
cross-origin-isolated page. Serve this directory from any other static server
and the game will fail to start with a SharedArrayBuffer error.
"""
import http.server
import os
import socketserver

PORT = 8099
DIRECTORY = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print("serving %s at http://127.0.0.1:%d/index.html" % (DIRECTORY, PORT))
    httpd.serve_forever()
