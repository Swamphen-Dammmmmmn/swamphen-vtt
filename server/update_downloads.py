"""Independent HTTPS static releases; no uploads, identities or business data."""
import http.server
import os
from pathlib import Path
import ssl
import threading
import time
import urllib.parse

ROOT=Path(os.environ.get("RELEASE_DIRECTORY","/releases")).resolve()
SLOTS=threading.BoundedSemaphore(2)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        parsed=urllib.parse.urlsplit(self.path)
        name=urllib.parse.unquote(parsed.path)
        if name.startswith('/stable/'):name=name[len('/stable/'):]
        else:self.send_error(404);return
        if '/' in name or '\\' in name or name not in {p.name for p in ROOT.iterdir() if p.is_file() and (p.suffix in ('.zip','.json','.sig'))}:
            self.send_error(404);return
        if not SLOTS.acquire(blocking=False):self.send_error(503);return
        try:
            path=ROOT/name
            if not path.resolve().is_relative_to(ROOT):self.send_error(404);return
            self.send_response(200)
            self.send_header('Content-Length',str(path.stat().st_size))
            self.send_header('Content-Type','application/octet-stream')
            self.send_header('Cache-Control','no-cache' if path.suffix in ('.json','.sig') else 'public, max-age=86400')
            self.end_headers()
            with path.open('rb') as stream:
                start=time.monotonic();written=0
                for block in iter(lambda:stream.read(65536),b''):
                    self.wfile.write(block);written+=len(block)
                    delay=written/(512*1024)-(time.monotonic()-start)
                    if delay>0:time.sleep(delay)
        except (BrokenPipeError,ConnectionResetError):pass
        finally:SLOTS.release()

class Server(http.server.ThreadingHTTPServer):
    daemon_threads=True
    def get_request(self):
        socket,address=super().get_request()
        socket.settimeout(20)
        return socket,address

def main():
    server=Server(('0.0.0.0',int(os.environ.get('PORT','10132'))),Handler)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain('/certs/public.crt','/certs/private.key')
    server.socket=context.wrap_socket(server.socket,server_side=True)
    server.serve_forever()

if __name__=='__main__':main()
