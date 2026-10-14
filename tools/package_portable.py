"""Build a signed portable ZIP from already-built boot and Godot directories."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/"launcher"))
import core

def write_signed(directory,record,key):
    raw=json.dumps(record,ensure_ascii=False,separators=(",",":"),sort_keys=True).encode()
    signature=base64.b64encode(key.sign(raw,padding.PSS(mgf=padding.MGF1(hashes.SHA256()),salt_length=padding.PSS.DIGEST_LENGTH),hashes.SHA256()))
    (directory/"release.json").write_bytes(raw)
    (directory/"release.sig").write_bytes(signature)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--init-key",action="store_true")
    parser.add_argument("--program",type=Path,default=ROOT/"build"/"portable-program")
    parser.add_argument("--boot",type=Path,default=ROOT/"build"/"portable-boot"/"紫水鸡棋盘")
    parser.add_argument("--version",default="0.1.1")
    parser.add_argument("--private-key",type=Path,default=ROOT/"artifacts"/"release-signing"/"private.pem")
    parser.add_argument("--output",type=Path,default=ROOT/"build"/"releases")
    parser.add_argument("--base-url",default="https://github.com/Swamphen-Dammmmmmn/swamphen-vtt/releases/download/v0.1.1/")
    parser.add_argument("--channel",choices=["stable","testing"],default="testing")
    parser.add_argument("--notes",default="临时生命值、棋子备注与转向；GitHub更新下载、手动导入及版本恢复。")
    args=parser.parse_args()
    core.version(args.version)
    if args.init_key:
        if args.private_key.exists():raise SystemExit("Existing signing key retained; initialization refused")
        args.private_key.parent.mkdir(parents=True,exist_ok=True)
        key=rsa.generate_private_key(public_exponent=65537,key_size=3072)
        args.private_key.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
        public=ROOT/"assets"/"updates"/"release-public.pem"
        public.parent.mkdir(parents=True,exist_ok=True)
        public.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo))
        print("Release signing key initialized; only public key belongs in version control.")
        return
    key=serialization.load_pem_private_key(args.private_key.read_bytes(),password=None)
    if key.key_size<3072:raise SystemExit("Production signing key too small")
    if not (args.program/core.ENTRY).exists() or not (args.boot/core.BOOT).exists():raise SystemExit("Build program and boot before packaging")
    args.output.mkdir(parents=True,exist_ok=True)
    stage=args.output/("payload-"+args.version)
    if stage.exists():raise SystemExit("Payload already exists; select a clean output directory")
    stage.mkdir()
    shutil.copytree(args.program,stage/"program")
    shutil.copytree(args.boot,stage/"boot")
    (stage/"boot"/"README.md").write_text("解压整个目录到可写位置，双击紫水鸡棋盘.exe。\n用户资料在userdata；更新不替换该目录。\n完整便携ZIP同时用于首次使用和程序内更新，源码ZIP不能更新。\n移动时请移动整个目录。\n",encoding="utf-8")
    initial_layout={"schema":1,"app":core.APP,"current":args.version,"previous":"","pending":False,"channel":args.channel}
    initial_bytes=json.dumps(initial_layout,ensure_ascii=False,separators=(",",":")).encode("utf-8")
    files={}
    for file in sorted(stage.rglob("*")):
        if file.is_file():files[file.relative_to(stage).as_posix()]={"size":file.stat().st_size,"sha256":core.sha(file)}
    record={"schema":1,"app":core.APP,"version":args.version,"platform":"win-x64","launcher_format":1,"protocol":1,"channel":args.channel,
            "data_formats":{"tokens":[1,2],"platforms":[1,2],"maps":[1],"adventures":[1]},
            "unpacked_size":sum(value["size"] for value in files.values()),"files":files,
            "notes":args.notes,"package_format":"portable-v1","portable_metadata":{"installation.json":{"size":len(initial_bytes),"sha256":hashlib.sha256(initial_bytes).hexdigest()}}}
    write_signed(stage,record,key)
    portable=args.output/("portable-"+args.version)
    portable.mkdir()
    for file in (stage/"boot").iterdir():
        if file.is_dir():shutil.copytree(file,portable/file.name)
        else:shutil.copy2(file,portable/file.name)
    version=portable/"versions"/args.version
    shutil.copytree(stage/"program",version)
    shutil.copy2(stage/"release.json",version/"release.json");shutil.copy2(stage/"release.sig",version/"release.sig")
    (portable/"installation.json").write_bytes(initial_bytes)
    initial=args.output/("svtt-"+args.version+"-windows-portable.zip")
    with zipfile.ZipFile(initial,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as package:
        for file in sorted(portable.rglob("*")):
            if file.is_file():package.write(file,"紫水鸡棋盘/"+file.relative_to(portable).as_posix())
    if not args.base_url.startswith("https://") or not args.base_url.endswith("/"):raise SystemExit("Provide HTTPS release download base URL ending in /")
    online=dict(record,url=args.base_url+initial.name,package_size=initial.stat().st_size,package_sha256=core.sha(initial))
    write_signed(args.output,online,key)
    print(json.dumps({"portable":str(initial),"portable_bytes":initial.stat().st_size}))

if __name__=="__main__":main()
