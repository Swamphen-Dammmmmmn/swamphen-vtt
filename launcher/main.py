from __future__ import annotations
import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid
import core

def resources():
    return Path(getattr(sys,"_MEIPASS",Path(__file__).resolve().parent))

def public_key():return (resources()/"release-public.pem").read_bytes()
def certificate():return None

def tell(message):
    if os.name=="nt":ctypes.windll.user32.MessageBoxW(None,str(message),"紫水鸡棋盘",0x10)
    elif sys.stderr:print(message,file=sys.stderr)

def process_exists(pid):
    if pid<=0:return False
    if os.name=="nt":
        kernel=ctypes.WinDLL("kernel32",use_last_error=True)
        kernel.OpenProcess.restype=ctypes.c_void_p
        handle=kernel.OpenProcess(0x1000,False,pid)
        if not handle:return False
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        kernel.CloseHandle(handle)
        return True
    try:os.kill(pid,0);return True
    except OSError:return False

def find_root():
    start=Path(sys.executable).parent if getattr(sys,"frozen",False) else Path(__file__).resolve().parent.parent
    for directory in [start,*start.parents]:
        if (directory/"installation.json").is_file():return directory
    return start

def worker(root,args):
    job=args.job
    if len(job)!=32 or any(c not in "0123456789abcdef" for c in job):raise core.UpdateError("任务编号无效。")
    result=root/"cache"/"updates"/"jobs"/(job+".json")
    def report(value):core.atomic_json(result,value)
    progress_time=[0.0]
    def progress(value):
        now=time.monotonic()
        fraction=value.get("progress",0) if isinstance(value,dict) else value
        if now-progress_time[0]<0.15 and fraction<1:return
        progress_time[0]=now
        detail=value if isinstance(value,dict) else {"phase":"verify","progress":value}
        report(dict(detail,state="working",message="正在下载更新" if detail.get("phase")=="download" else "正在校验更新"))
    report({"state":"working","message":"正在检查更新","progress":0})
    try:
        if args.action=="check":
            record,_,_=core.check(root,public_key(),certificate())
            current=core.read_json(root/"installation.json")["current"]
            available=core.version(record["version"])>core.version(current)
            report({"state":"available" if available else "current","message":"发现新版本" if available else "已是当前版本","version":record["version"],"notes":record.get("notes","")})
        elif args.action=="download":
            record,_,_=core.check(root,public_key(),certificate())
            record=core.download(root,record,public_key(),certificate(),progress)
            report({"state":"staged","message":"更新已就绪","version":record["version"],"notes":record.get("notes","")})
        elif args.action=="import":
            record=core.stage(root,Path(args.package),public_key(),progress)
            report({"state":"staged","message":"更新已就绪","version":record["version"],"notes":record.get("notes","")})
    except Exception as error:
        message=str(error) if isinstance(error,core.UpdateError) else "更新失败，请检查连接、文件与目录权限。当前程序和数据已保留。"
        report({"state":"failed","message":message})

def launch(root):
    layout=core.read_json(root/"installation.json")
    if layout.get("app")!=core.APP:raise core.UpdateError("程序目录标记无效。")
    core.version(layout["current"])
    if ((root/"cache"/"updates"/"transaction.json").exists() and not layout.get("pending")) or Path(sys.executable).parent.name=="boot-backup":
        helper(root,"recover",os.getpid())
        return
    entry=core.child(root,"versions/"+layout["current"]+"/"+core.ENTRY)
    if not entry.is_file():raise core.UpdateError("当前程序文件缺失，请重新解压完整ZIP，保留userdata目录。")
    ticket=uuid.uuid4().hex
    ready=root/"cache"/"sessions"/(ticket+".ready")
    lease=ready.with_suffix(".lock")
    (root/"logs").mkdir(parents=True,exist_ok=True)
    with core.exclusive(lease):
        with core.exclusive(root/"cache"/"updates"/"launch.lock"):
            with (root/"logs"/(ticket+".log")).open("wb") as log:
                proc=subprocess.Popen([str(entry),"--log-file",str(root/"logs"/(ticket+"-godot.log")),"--","--launch-ticket="+ticket],cwd=entry.parent,stdout=log,stderr=log)
            start=time.monotonic()
            while not ready.exists() and proc.poll() is None and time.monotonic()-start<90:time.sleep(.1)
            acknowledged=ready.exists()
            if acknowledged and layout.get("pending"):core.confirm(root)
        if not acknowledged and proc.poll() is not None:
            if layout.get("pending"):
                helper(root,"recover",os.getpid())
                return
            raise core.UpdateError("程序未完成初始化。请查看logs目录，用户数据已保留。")
        proc.wait()
    ready.unlink(missing_ok=True)
    lease.unlink(missing_ok=True)

def helper(root,action,wait_pid):
    if not getattr(sys,"frozen",False):raise core.UpdateError("更新应用仅在ZIP发布版本可用。")
    target=root/"cache"/"updates"/"helpers"/uuid.uuid4().hex
    target.mkdir(parents=True)
    executable=target/core.BOOT
    shutil.copy2(sys.executable,executable)
    shutil.copytree(resources(),target/"_internal")
    subprocess.Popen([str(executable),"--action",action,"--root",str(root),"--wait-pid",str(wait_pid),"--helper"],cwd=target,creationflags=0x08000000)

def perform(root,args):
    deadline=time.monotonic()+120
    while process_exists(args.wait_pid) and time.monotonic()<deadline:time.sleep(.2)
    if process_exists(args.wait_pid):raise core.UpdateError("程序尚未退出，本次更新未应用。")
    # Parent launchers release their leases after the game exits.
    for _ in range(50):
        try:core.assert_idle(root);break
        except core.UpdateError:time.sleep(.1)
    core.assert_idle(root)
    if args.action=="apply":core.apply(root,public_key())
    elif args.action=="rollback":core.rollback(root,public_key())
    elif args.action=="recover":
        with core.exclusive(root/"cache"/"updates"/"work.lock"):core.recover(root)
        tell("新版本未完成启动，已恢复原程序版本。用户数据未被回退。")
    subprocess.Popen([str(root/core.BOOT)],cwd=root,creationflags=0x08000000)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--action",default="launch",choices=["launch","check","download","import","apply","rollback","recover"])
    parser.add_argument("--root",default="")
    parser.add_argument("--job",default="")
    parser.add_argument("--package",default="")
    parser.add_argument("--wait-pid",type=int,default=0)
    parser.add_argument("--helper",action="store_true")
    args=parser.parse_args()
    root=Path(args.root).resolve() if args.root else find_root()
    try:
        if args.action=="launch":launch(root)
        elif args.action in ("apply","rollback","recover"):
            if not args.helper:helper(root,args.action,args.wait_pid)
            else:perform(root,args)
        else:worker(root,args)
    except Exception as error:
        tell(str(error) if isinstance(error,core.UpdateError) else "程序启动或更新失败，请保留userdata并查看日志，重新解压完整ZIP可修复程序文件。")
        return 1
    return 0

if __name__=="__main__":raise SystemExit(main())
