import http.server
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{self.address_string()}] {args[0]} {args[1]} {args[2]}")

    def do_GET(self):
        print(f"[+] {self.path}")
        return super().do_GET()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"[*] Kitty Hub server running on http://localhost:{PORT}")
    print(f"[*] Loadstring:")
    print(f'    loadstring(game:HttpGet("http://localhost:{PORT}/kittyhub.lua"))()')
    print()
    httpd.serve_forever()
