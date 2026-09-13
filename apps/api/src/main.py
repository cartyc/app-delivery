"""api: a second in-house demo service, on the golden python base.

Standard library only (no pip installs) so it builds straight on the distroless
golden python image.
"""
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        body = json.dumps(
            {
                "app": "api",
                "env": os.getenv("APP_ENV", ""),
                "version": os.getenv("APP_VERSION", ""),
                "time": datetime.now(timezone.utc).isoformat(),
            }
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # quiet default logging
        pass


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    print(f"api listening on :{port}", flush=True)
    ThreadingHTTPServer(("", port), Handler).serve_forever()
