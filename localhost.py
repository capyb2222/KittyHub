import http.server
import socketserver
import sys
import datetime

if __name__ == "__main__":
    try:
        PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
        if PORT < 1 or PORT > 65535:
            print(f"Error: port must be between 1 and 65535, got {PORT}")
            sys.exit(1)
    except ValueError:
        print(f"Error: invalid port '{sys.argv[1] if len(sys.argv) > 1 else ''}' — must be an integer")
        sys.exit(1)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            super().do_GET()

        def log_message(self, fmt, *args):
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            msg = fmt % args if args else fmt
            print(f"[{timestamp}] {self.address_string()} - {msg}", file=sys.stderr)

    try:
        httpd = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        print(f"Error: could not bind to port {PORT} — {e}")
        sys.exit(1)

    print(f"[*] Kitty Hub server running on http://localhost:{PORT}")
    print(f"[*] Loadstring:")
    print(f'    loadstring(game:HttpGet("http://localhost:{PORT}/kittyhub.lua"))()')
    print()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down...", file=sys.stderr)
    finally:
        httpd.server_close()
