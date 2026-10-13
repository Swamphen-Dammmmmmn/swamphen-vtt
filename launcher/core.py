"""Portable release verification and transaction logic; no game or identity traffic."""
from __future__ import annotations
import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import ssl
import tempfile
import time
import urllib.request
import uuid
import zipfile
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

APP = "purplehen-board"
FORMAT = 1
MAX_PACKAGE = 1024 * 1024 * 1024
MAX_EXPANDED = 3 * 1024 * 1024 * 1024
MAX_MANIFEST = 4 * 1024 * 1024
ENTRY = "棋盘.exe"
BOOT = "紫水鸡棋盘.exe"
UPDATE_URL = ""

class UpdateError(Exception):
    pass

def read_json(path: Path):
    if path.stat().st_size > MAX_MANIFEST:
        raise UpdateError("版本信息超过大小限制。")
    return json.loads(path.read_text(encoding="utf-8-sig"))

def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, separators=(",", ":"))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)

def version(value):
    if not isinstance(value, str): raise UpdateError("版本号无效。")
    parts = value.split(".")
    if len(parts) != 3 or any(not s.isascii() or not s.isdecimal() or len(s)>5 for s in parts):
        raise UpdateError("仅支持三段数字的正式版本号。")
    return tuple(map(int, parts))

def child(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative or ":" in relative:
        raise UpdateError("文件路径无效。")
    parts = PurePosixPath(relative).parts
    if relative.startswith("/") or any(s in (".", "..", "") or s.endswith((" ",".")) for s in parts):
        raise UpdateError("更新包含越界路径。")
    for part in parts:
        stem=part.split(".")[0].upper()
        if stem in {"CON","PRN","AUX","NUL",*(f"COM{i}" for i in range(1,10)),*(f"LPT{i}" for i in range(1,10))}:
            raise UpdateError("更新包含Windows保留路径。")
    result = root.joinpath(*parts)
    if not result.resolve().is_relative_to(root.resolve()): raise UpdateError("更新路径超出程序目录。")
    return result

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""): digest.update(block)
    return digest.hexdigest()

def verified(raw: bytes, signature: bytes, public_pem: bytes):
    if len(raw)>MAX_MANIFEST or len(signature)>4096: raise UpdateError("版本清单无效。")
    try:
        key = serialization.load_pem_public_key(public_pem)
        key.verify(base64.b64decode(signature,validate=True), raw,
                   padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=padding.PSS.DIGEST_LENGTH), hashes.SHA256())
        record = json.loads(raw)
    except Exception as error:
        raise UpdateError("更新发布签名无效，未改动当前程序。") from error
    if record.get("app")!=APP or record.get("schema")!=FORMAT or record.get("platform")!="win-x64":
        raise UpdateError("更新包不适用于本程序或平台。")
    version(record.get("version"))
    if record.get("launcher_format")!=FORMAT: raise UpdateError("需要下载新版完整ZIP以更新启动器。")
    files=record.get("files")
    if not isinstance(files,dict) or not 1<=len(files)<=20000: raise UpdateError("更新文件清单无效。")
    total=0
    folded=set()
    for name, entry in files.items():
        child(Path.cwd(),name)
        if not name.startswith(("program/","boot/")) or name.lower() in folded:
            raise UpdateError("更新文件清单包含非法或重复路径。")
        folded.add(name.lower())
        if not isinstance(entry,dict) or type(entry.get("size")) is not int or not 0<=entry["size"]<=MAX_PACKAGE:
            raise UpdateError("文件大小无效。")
        h=entry.get("sha256")
        if not isinstance(h,str) or len(h)!=64 or any(c not in "0123456789abcdef" for c in h):
            raise UpdateError("文件校验信息无效。")
        total+=entry["size"]
    if total>MAX_EXPANDED or "program/"+ENTRY not in files or "boot/"+BOOT not in files:
        raise UpdateError("更新超过预算或缺少程序入口。")
    if record.get("unpacked_size")!=total: raise UpdateError("更新大小与清单不符。")
    formats=record.get("data_formats")
    if not isinstance(formats,dict) or any(not isinstance(formats.get(k),list) or not formats[k] or any(type(v) is not int for v in formats[k]) for k in ("tokens","platforms","maps","adventures")):
        raise UpdateError("缺少数据兼容说明。")
    return record

def assert_compatible(root: Path, record):
    for kind, supported in record["data_formats"].items():
        if kind not in ("tokens","platforms","maps","adventures"): continue
        directory=root/"userdata"/"products"/kind
        if not directory.exists():continue
        for path in directory.glob("*.json"):
            if path.stat().st_size>512*1024*1024: raise UpdateError("存档超过兼容检查预算。")
            try:
                with path.open(encoding="utf-8-sig") as stream:data=json.load(stream)
                file_version=data.get("format_version")
                if type(file_version) not in (int,float) or file_version not in supported:
                    raise ValueError()
            except Exception as error:
                raise UpdateError(f"不能确认{path.name}与目标版本兼容。未切换程序，数据已保留。") from error

def space(root: Path, required: int):
    if shutil.disk_usage(root).free < required + 64*1024*1024: raise UpdateError("剩余磁盘空间不足，当前版本保留。")

@contextlib.contextmanager
def exclusive(path: Path):
    path.parent.mkdir(parents=True,exist_ok=True)
    file=path.open("a+b")
    try:
        if os.name=="nt":
            import msvcrt
            file.seek(0); file.write(b"0"); file.flush(); file.seek(0)
            msvcrt.locking(file.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(file,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except OSError as error:
        file.close(); raise UpdateError("程序正在使用或另一次更新尚未完成。") from error
    try: yield
    finally:
        if os.name=="nt":
            file.seek(0); msvcrt.locking(file.fileno(),msvcrt.LK_UNLCK,1)
        else:
            import fcntl
            fcntl.flock(file,fcntl.LOCK_UN)
        file.close()

def assert_idle(root: Path):
    sessions=root/"cache"/"sessions"
    if sessions.exists():
        for lease in sessions.glob("*.lock"):
            with exclusive(lease):pass
    if os.name=="nt":
        import ctypes
        from ctypes import wintypes
        kernel=ctypes.WinDLL("kernel32",use_last_error=True)
        kernel.OpenProcess.restype=ctypes.c_void_p
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        kernel.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
        ids=(wintypes.DWORD*4096)();used=wintypes.DWORD()
        if ctypes.windll.psapi.EnumProcesses(ids,ctypes.sizeof(ids),ctypes.byref(used)):
            base=str((root/"versions").resolve()).casefold()+os.sep
            for pid in ids[:used.value//ctypes.sizeof(wintypes.DWORD)]:
                handle=kernel.OpenProcess(0x1000,False,pid)
                if not handle:continue
                try:
                    buffer=ctypes.create_unicode_buffer(32768);length=wintypes.DWORD(32768)
                    if kernel.QueryFullProcessImageNameW(handle,0,buffer,ctypes.byref(length)) and buffer.value.casefold().startswith(base):
                        raise UpdateError("同一程序目录还有运行中的窗口，请先退出。")
                finally:kernel.CloseHandle(handle)

def ssl_context(certificate: Path):
    context=ssl.create_default_context()
    context.load_verify_locations(cafile=str(certificate))
    return context

def fetch(url: str, certificate: Path, limit: int):
    if not isinstance(url,str) or not url.startswith("https://"): raise UpdateError("更新地址必须使用HTTPS。")
    with urllib.request.urlopen(url,context=ssl_context(certificate),timeout=30) as response:
        if not response.url.startswith("https://"):raise UpdateError("更新跳转至非HTTPS地址。")
        data=response.read(limit+1)
        if len(data)>limit:raise UpdateError("下载内容超过限制。")
        return data

def check(root: Path, public: bytes, certificate: Path):
    config=root/"userdata"/"updates.json"
    url=read_json(config).get("url",UPDATE_URL) if config.exists() else UPDATE_URL
    if not url: raise UpdateError("未配置程序分发地址，可使用离线更新ZIP。")
    if not url.endswith("release.json"):raise UpdateError("更新清单地址无效。")
    raw=fetch(url,certificate,MAX_MANIFEST)
    signature=fetch(url[:-4]+"sig",certificate,4096)
    record=verified(raw,signature,public)
    return record,raw,signature

def stage(root: Path, archive: Path, public: bytes, progress=lambda value:None):
    if archive.stat().st_size>MAX_PACKAGE:raise UpdateError("更新ZIP超过大小限制。")
    with exclusive(root/"cache"/"updates"/"work.lock"):
        with zipfile.ZipFile(archive) as package:
            entries=package.infolist()
            if len(entries)>20002:raise UpdateError("更新ZIP文件过多。")
            if package.getinfo("release.json").file_size>MAX_MANIFEST or package.getinfo("release.sig").file_size>4096:
                raise UpdateError("清单超过预算。")
            raw=package.read("release.json"); signature=package.read("release.sig")
            record=verified(raw,signature,public)
            layout=read_json(root/"installation.json")
            if version(record["version"])<=version(layout["current"]):raise UpdateError("更新版本不高于当前版本。")
            assert_compatible(root,record)
            actual=[entry for entry in entries if not entry.is_dir()]
            names=[entry.filename for entry in actual]
            if len(names)!=len(set(names)) or set(names)!=set(record["files"])|{"release.json","release.sig"}:
                raise UpdateError("更新ZIP与发布清单不符。")
            for entry in entries:
                child(root,entry.filename.rstrip("/"))
                if ((entry.external_attr>>16)&0o170000)==0o120000:raise UpdateError("更新ZIP包含链接。")
            space(root,record["unpacked_size"]*2)
            target=root/"cache"/"updates"/"staged"/uuid.uuid4().hex
            target.mkdir(parents=True)
            try:
                done=0
                for entry in actual:
                    if entry.filename in ("release.json","release.sig"):continue
                    expected=record["files"][entry.filename]
                    if entry.file_size!=expected["size"]:raise UpdateError("ZIP声明的文件大小不符。")
                    destination=child(target,entry.filename)
                    destination.parent.mkdir(parents=True,exist_ok=True)
                    digest=hashlib.sha256();written=0
                    with package.open(entry) as source,destination.open("wb") as output:
                        for block in iter(lambda:source.read(1024*1024),b""):
                            written+=len(block)
                            if written>expected["size"]:raise UpdateError("解压内容超出清单。")
                            digest.update(block);output.write(block)
                    if written!=expected["size"] or digest.hexdigest()!=expected["sha256"]:raise UpdateError("更新文件校验失败。")
                    done+=written;progress(done/max(1,record["unpacked_size"]))
                (target/"release.json").write_bytes(raw);(target/"release.sig").write_bytes(signature)
                atomic_json(root/"cache"/"updates"/"staged.json",{"path":target.relative_to(root).as_posix(),"version":record["version"]})
                return record
            except Exception:
                shutil.rmtree(target)
                raise

def download(root: Path, record, public: bytes, certificate: Path, progress=lambda value:None):
    size=record.get("package_size"); url=record.get("url"); digest=record.get("package_sha256")
    if type(size) is not int or not 1<=size<=MAX_PACKAGE or not isinstance(url,str) or not url.startswith("https://"):
        raise UpdateError("在线更新信息不完整。")
    space(root,size+record["unpacked_size"]*2)
    path=root/"cache"/"updates"/"download.zip"
    path.parent.mkdir(parents=True,exist_ok=True)
    h=hashlib.sha256();done=0
    with exclusive(root/"cache"/"updates"/"download.lock"):
        with urllib.request.urlopen(url,context=ssl_context(certificate),timeout=30) as source,path.open("wb") as destination:
            if not source.url.startswith("https://"):raise UpdateError("下载跳转地址无效。")
            for block in iter(lambda:source.read(256*1024),b""):
                done+=len(block)
                if done>size:raise UpdateError("下载超过发布大小。")
                destination.write(block);h.update(block);progress(done/size*.65)
        if done!=size or h.hexdigest()!=digest:raise UpdateError("下载未完成或校验失败。")
        result=stage(root,path,public,lambda value:progress(.65+value*.35))
        if result["version"]!=record["version"]:raise UpdateError("在线清单与包版本不符。")
        return result

def staged_record(root: Path, public: bytes):
    staged=read_json(root/"cache"/"updates"/"staged.json")
    if not str(staged.get("path","")).startswith("cache/updates/staged/"):raise UpdateError("暂存目录无效。")
    target=child(root,staged["path"])
    record=verified((target/"release.json").read_bytes(),(target/"release.sig").read_bytes(),public)
    for name,info in record["files"].items():
        file=child(target,name)
        if file.stat().st_size!=info["size"] or sha(file)!=info["sha256"]:raise UpdateError("暂存文件已变化，未应用更新。")
    return target,record

def apply(root: Path, public: bytes):
    with exclusive(root/"cache"/"updates"/"work.lock"):
        assert_idle(root)
        target,record=staged_record(root,public)
        layout=read_json(root/"installation.json")
        if version(record["version"])<=version(layout["current"]):raise UpdateError("暂存版本已过期。")
        assert_compatible(root,record)
        destination=child(root,"versions/"+record["version"])
        if destination.exists():raise UpdateError("目标版本目录已存在，未覆盖。")
        backup=root/"cache"/"updates"/"boot-backup"
        if backup.exists():raise UpdateError("存在未完成的启动器恢复，请先修复。")
        changes=[]
        for source in (target/"boot").iterdir():
            old=root/source.name
            # Boot names are publisher-signed, but user data cannot be a boot file.
            if source.name not in (BOOT,"_internal","licenses","THIRD_PARTY_NOTICES.md"):raise UpdateError("启动器文件布局无效。")
            changes.append((source,old))
        backup.mkdir(parents=True)
        journal=root/"cache"/"updates"/"transaction.json"
        atomic_json(journal,{"layout":layout,"version":record["version"],"boot":[old.name for _,old in changes]})
        try:
            os.replace(target/"program",destination)
            (destination/"release.json").write_bytes((target/"release.json").read_bytes())
            (destination/"release.sig").write_bytes((target/"release.sig").read_bytes())
            for source,old in changes:
                if old.exists():os.replace(old,backup/old.name)
                os.replace(source,old)
            next_layout=dict(layout,current=record["version"],previous=layout["current"],pending=True)
            atomic_json(root/"installation.json",next_layout)
        except Exception:
            recover(root)
            raise
        # Keep boot backup until the new application acknowledges initialization.
        return record

def recover(root: Path):
    journal=root/"cache"/"updates"/"transaction.json"
    if not journal.exists():return
    record=read_json(journal)
    version(record["version"])
    backup=root/"cache"/"updates"/"boot-backup"
    for name in record["boot"]:
        if name not in (BOOT,"_internal","licenses","THIRD_PARTY_NOTICES.md"):raise UpdateError("恢复清单无效。")
        saved=backup/name;current=root/name
        if saved.exists():
            if current.is_dir():shutil.rmtree(current)
            elif current.exists():current.unlink()
            os.replace(saved,current)
    atomic_json(root/"installation.json",record["layout"])
    installed=child(root,"versions/"+record["version"])
    if installed.exists():shutil.rmtree(installed)
    if backup.exists():shutil.rmtree(backup)
    journal.unlink()

def confirm(root: Path):
    layout=read_json(root/"installation.json")
    if not layout.get("pending"):return
    atomic_json(root/"installation.json",dict(layout,pending=False))
    for relative in ("cache/updates/boot-backup","cache/updates/staged"):
        path=child(root,relative)
        if path.exists():shutil.rmtree(path)
    for relative in ("cache/updates/transaction.json","cache/updates/staged.json"):
        path=root/relative
        if path.exists():path.unlink()
    keep={layout["current"],layout.get("previous","")}
    for directory in (root/"versions").iterdir():
        if directory.name in keep or not directory.is_dir():continue
        try:version(directory.name)
        except UpdateError:continue
        if not directory.resolve().is_relative_to((root/"versions").resolve()):continue
        if (directory/"release.json").exists():
            try:shutil.rmtree(directory)
            except OSError:pass

def rollback(root: Path, public: bytes):
    with exclusive(root/"cache"/"updates"/"work.lock"):
        assert_idle(root)
        layout=read_json(root/"installation.json")
        previous=layout.get("previous","")
        version(previous)
        path=child(root,"versions/"+previous)
        record=verified((path/"release.json").read_bytes(),(path/"release.sig").read_bytes(),public)
        assert_compatible(root,record)
        atomic_json(root/"installation.json",dict(layout,current=previous,previous=layout["current"],pending=False))
        return record
