"""Download the pinned official Godot build and Windows export template."""
import concurrent.futures
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import re
import zipfile

VERSION = "4.7.2"
BASE = f"https://godot-releases.nbg1.your-objectstorage.com/{VERSION}-stable/"
INSTALL = Path(os.environ["LOCALAPPDATA"]) / "Programs" / "Godot"


def resolve(url):
    headers = subprocess.check_output(["curl.exe", "-sS", "-I", "-L", "--fail", "--retry", "3", "--retry-all-errors",
                                       "--max-time", "30", "-w", "\nURL:%{url_effective}", url], text=True)
    length = int(re.findall(r"(?im)^content-length:\s*(\d+)", headers)[-1])
    return headers.rsplit("URL:", 1)[1].strip(), length


def fetch(url, start, end):
    with tempfile.NamedTemporaryFile(delete=False) as part:
        path = part.name
    try:
        subprocess.run(["curl.exe", "-sS", "-L", "--fail", "--retry", "3", "--retry-all-errors",
                        "--max-time", "240", "-r", f"{start}-{end}", "-o", path, url], check=True)
        data = Path(path).read_bytes()
        if len(data) != end - start + 1:
            raise RuntimeError(f"Range length mismatch: {len(data)}")
        return data
    finally:
        Path(path).unlink(missing_ok=True)


def parallel_fetch(url, start, length):
    chunk = 2 * 1024 * 1024
    ranges = [(offset, min(offset + chunk, start + length) - 1)
              for offset in range(start, start + length, chunk)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        return b"".join(pool.map(lambda bounds: fetch(url, *bounds), ranges))


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        self.url, self.length = resolve(url)
        self.position = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.length + offset
        return self.position

    def tell(self):
        return self.position

    def read(self, size=-1):
        size = min(self.length - self.position, size if size >= 0 else self.length)
        if size <= 0:
            return b""
        result = parallel_fetch(self.url, self.position, size)
        self.position += len(result)
        return result


def install_editor():
    INSTALL.mkdir(parents=True, exist_ok=True)
    url, length = resolve(BASE + f"Godot_v{VERSION}-stable_win64.exe.zip")
    print(f"Downloading official Godot {VERSION}: {length / 1048576:.1f} MiB", flush=True)
    data = parallel_fetch(url, 0, length)
    expected = "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953"
    if hashlib.sha256(data).hexdigest() != expected:
        raise RuntimeError("Official editor SHA256 mismatch")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        archive.extractall(INSTALL)
    print(f"Editor installed: {INSTALL}", flush=True)


def install_template():
    dest = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{VERSION}.stable"
    dest.mkdir(parents=True, exist_ok=True)
    print("Reading official export template archive (Windows release only)", flush=True)
    with zipfile.ZipFile(RemoteZip(BASE + f"Godot_v{VERSION}-stable_export_templates.tpz")) as archive:
        for name in ["windows_release_x86_64.exe", "version.txt"]:
            match = next(item for item in archive.namelist() if item.endswith("/" + name))
            (dest / name).write_bytes(archive.read(match))
            print(f"Installed template: {name}", flush=True)


if __name__ == "__main__":
    install_template() if "--templates" in sys.argv else install_editor()
